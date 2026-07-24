use crate::limits::{LimitError, LimitTracker, RuntimeLimits};
use crate::runner_client::RunnerClient;
use atlas_plugin_package::VerifiedPackage;
use atlas_plugin_protocol::{
    CapabilityResponse, CommandStart, Envelope, MessageKind, ResourceMetric,
};
use atlas_ui_schema::UiEvent;
use std::collections::{HashMap, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, RwLock};
use std::time::{Duration, Instant};

const BREAKER_WINDOW: Duration = Duration::from_secs(10 * 60);
const BREAKER_FAILURES: usize = 3;
const STARTUP_FAILURES_TO_DISABLE: u8 = 2;
const MAX_DISPATCH_MESSAGES: usize = 512;

pub trait Clock: Send + Sync {
    fn now(&self) -> Duration;
}

pub struct MonotonicClock {
    started_at: Instant,
}

impl Default for MonotonicClock {
    fn default() -> Self {
        Self {
            started_at: Instant::now(),
        }
    }
}

impl Clock for MonotonicClock {
    fn now(&self) -> Duration {
        self.started_at.elapsed()
    }
}

pub trait ManagedRunner: Send {
    fn send(&mut self, envelope: &Envelope) -> Result<(), SupervisorError>;
    fn receive(&mut self) -> Result<Envelope, SupervisorError>;
    fn is_running(&mut self) -> Result<bool, SupervisorError>;
    fn stop(&mut self);
}

impl ManagedRunner for RunnerClient {
    fn send(&mut self, envelope: &Envelope) -> Result<(), SupervisorError> {
        RunnerClient::send(self, envelope)
            .map_err(|error| SupervisorError::Runner(error.to_string()))
    }

    fn receive(&mut self) -> Result<Envelope, SupervisorError> {
        RunnerClient::receive(self).map_err(|error| SupervisorError::Runner(error.to_string()))
    }

    fn is_running(&mut self) -> Result<bool, SupervisorError> {
        RunnerClient::is_running(self).map_err(|error| SupervisorError::Runner(error.to_string()))
    }

    fn stop(&mut self) {
        self.terminate();
    }
}

pub trait RunnerLauncher: Send + Sync {
    fn launch(
        &self,
        package: &VerifiedPackage,
        limits: &RuntimeLimits,
    ) -> Result<Box<dyn ManagedRunner>, SupervisorError>;
}

pub struct ProcessRunnerLauncher {
    runner_path: PathBuf,
}

impl ProcessRunnerLauncher {
    pub fn new(runner_path: impl Into<PathBuf>) -> Self {
        Self {
            runner_path: runner_path.into(),
        }
    }

    pub fn runner_path(&self) -> &Path {
        &self.runner_path
    }
}

impl RunnerLauncher for ProcessRunnerLauncher {
    fn launch(
        &self,
        package: &VerifiedPackage,
        limits: &RuntimeLimits,
    ) -> Result<Box<dyn ManagedRunner>, SupervisorError> {
        RunnerClient::launch(&self.runner_path, package, limits.clone())
            .map(|runner| Box::new(runner) as Box<dyn ManagedRunner>)
            .map_err(|error| SupervisorError::Runner(error.to_string()))
    }
}

#[derive(Debug, Clone)]
pub struct CommandInvocation {
    pub plugin_id: String,
    pub command_id: String,
    pub instance_id: String,
    pub start: CommandStart,
    pub restartable: bool,
    pub background: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommandHandle {
    pub plugin_id: String,
    pub command_id: String,
    pub instance_id: String,
    pub generation: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CommandStatus {
    Running,
    Recovering,
    Failed,
    OutcomeUnknown,
    Cancelled,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Termination {
    Crash,
    Limit,
    Protocol,
    Requested,
}

impl Termination {
    fn unexpected(self) -> bool {
        matches!(self, Self::Crash | Self::Limit | Self::Protocol)
    }

    fn opens_breaker(self) -> bool {
        matches!(self, Self::Crash | Self::Limit)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RecoveryReport {
    pub restarted: bool,
    pub recovered_instances: Vec<String>,
    pub outcome_unknown_instances: Vec<String>,
}

#[derive(Debug, thiserror::Error)]
pub enum SupervisorError {
    #[error("plugin `{0}` has no active Runner generation")]
    PluginNotActive(String),
    #[error("plugin `{0}` is disabled after repeated startup failures")]
    PluginDisabled(String),
    #[error("command `{plugin_id}/{command_id}` circuit breaker is open")]
    CircuitOpen {
        plugin_id: String,
        command_id: String,
    },
    #[error("command instance `{0}` does not exist")]
    CommandNotFound(String),
    #[error("background command is scheduled more often than once per minute")]
    BackgroundSchedule,
    #[error("Runner failed: {0}")]
    Runner(String),
    #[error("resource limit failed: {0}")]
    Limit(#[from] LimitError),
    #[error("supervisor state lock is poisoned")]
    LockPoisoned,
    #[error("interrupted write has unknown outcome and cannot be replayed")]
    OutcomeUnknown,
    #[error("plugin writes are frozen for package migration")]
    WritesFrozen,
    #[error("Runner protocol violation: {0}")]
    Protocol(String),
}

struct RunnerGeneration {
    id: u64,
    package: Arc<VerifiedPackage>,
    runner: Box<dyn ManagedRunner>,
    limits: RuntimeLimits,
    tracker: LimitTracker,
    last_used: Duration,
    restart_attempts: u8,
}

struct CommandState {
    invocation: CommandInvocation,
    generation: u64,
    status: CommandStatus,
    incomplete_write: bool,
}

#[derive(Default)]
struct PluginState {
    active: Option<RunnerGeneration>,
    retiring: Vec<RunnerGeneration>,
    commands: HashMap<String, CommandState>,
    resident: bool,
    writes_frozen: bool,
    disabled: bool,
    startup_failures: u8,
}

impl PluginState {
    fn generation_mut(&mut self, generation: u64) -> Option<&mut RunnerGeneration> {
        if self
            .active
            .as_ref()
            .is_some_and(|item| item.id == generation)
        {
            return self.active.as_mut();
        }
        self.retiring.iter_mut().find(|item| item.id == generation)
    }

    fn retire_unused(&mut self) {
        let commands = &self.commands;
        self.retiring.retain_mut(|generation| {
            if commands
                .values()
                .any(|command| command.generation == generation.id)
            {
                true
            } else {
                generation.runner.stop();
                false
            }
        });
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct CommandKey {
    plugin_id: String,
    command_id: String,
}

#[derive(Default)]
struct CircuitBreaker {
    failures: VecDeque<Duration>,
    open: bool,
}

impl CircuitBreaker {
    fn record(&mut self, now: Duration) {
        let cutoff = now.saturating_sub(BREAKER_WINDOW);
        while self
            .failures
            .front()
            .is_some_and(|timestamp| *timestamp < cutoff)
        {
            self.failures.pop_front();
        }
        self.failures.push_back(now);
        self.open = self.failures.len() >= BREAKER_FAILURES;
    }

    fn reset(&mut self) {
        self.failures.clear();
        self.open = false;
    }
}

pub struct PluginSupervisor {
    launcher: Arc<dyn RunnerLauncher>,
    clock: Arc<dyn Clock>,
    plugins: RwLock<HashMap<String, Arc<Mutex<PluginState>>>>,
    breakers: Mutex<HashMap<CommandKey, CircuitBreaker>>,
    background_runs: Mutex<HashMap<CommandKey, Duration>>,
    next_generation: AtomicU64,
}

impl PluginSupervisor {
    pub fn new(launcher: Arc<dyn RunnerLauncher>, clock: Arc<dyn Clock>) -> Self {
        Self {
            launcher,
            clock,
            plugins: RwLock::new(HashMap::new()),
            breakers: Mutex::new(HashMap::new()),
            background_runs: Mutex::new(HashMap::new()),
            next_generation: AtomicU64::new(1),
        }
    }

    pub fn activate_generation(
        &self,
        package: Arc<VerifiedPackage>,
    ) -> Result<u64, SupervisorError> {
        let plugin_id = package.plugin_id().to_owned();
        let limits = RuntimeLimits::for_runtime(package.manifest().runtime);
        let mut runner = match self.launcher.launch(&package, &limits) {
            Ok(runner) => runner,
            Err(error) => {
                self.note_startup_failure(&plugin_id)?;
                return Err(error);
            }
        };
        if let Err(error) = verify_health(runner.as_mut(), &plugin_id) {
            runner.stop();
            self.note_startup_failure(&plugin_id)?;
            return Err(error);
        }
        let generation_id = self.next_generation.fetch_add(1, Ordering::SeqCst);
        let now = self.clock.now();
        let state = self.plugin_state_or_insert(&plugin_id)?;
        let mut state = state.lock().map_err(|_| SupervisorError::LockPoisoned)?;
        if state.disabled {
            runner.stop();
            return Err(SupervisorError::PluginDisabled(plugin_id));
        }
        if let Some(previous) = state.active.take() {
            state.retiring.push(previous);
        }
        state.startup_failures = 0;
        state.active = Some(RunnerGeneration {
            id: generation_id,
            package,
            runner,
            tracker: LimitTracker::new(limits.clone()),
            limits,
            last_used: now,
            restart_attempts: 0,
        });
        state.retire_unused();
        Ok(generation_id)
    }

    pub fn start_command(
        &self,
        invocation: CommandInvocation,
    ) -> Result<CommandHandle, SupervisorError> {
        if self.command_disabled(&invocation.plugin_id, &invocation.command_id) {
            return Err(SupervisorError::CircuitOpen {
                plugin_id: invocation.plugin_id,
                command_id: invocation.command_id,
            });
        }
        if invocation.background
            && !self.can_schedule_background(&invocation.plugin_id, &invocation.command_id)
        {
            return Err(SupervisorError::BackgroundSchedule);
        }
        let state = self
            .plugin_state(&invocation.plugin_id)?
            .ok_or_else(|| SupervisorError::PluginNotActive(invocation.plugin_id.clone()))?;
        let mut state = state.lock().map_err(|_| SupervisorError::LockPoisoned)?;
        if state.disabled {
            return Err(SupervisorError::PluginDisabled(invocation.plugin_id));
        }
        let generation = state
            .active
            .as_mut()
            .ok_or_else(|| SupervisorError::PluginNotActive(invocation.plugin_id.clone()))?;
        let generation_id = generation.id;
        generation.runner.send(&Envelope::new(
            &invocation.plugin_id,
            &invocation.command_id,
            &invocation.instance_id,
            format!("start-{}", invocation.instance_id),
            MessageKind::Start(invocation.start.clone()),
        ))?;
        generation.last_used = self.clock.now();
        let handle = CommandHandle {
            plugin_id: invocation.plugin_id.clone(),
            command_id: invocation.command_id.clone(),
            instance_id: invocation.instance_id.clone(),
            generation: generation_id,
        };
        state.commands.insert(
            invocation.instance_id.clone(),
            CommandState {
                invocation,
                generation: generation_id,
                status: CommandStatus::Running,
                incomplete_write: false,
            },
        );
        Ok(handle)
    }

    pub fn start_command_and_collect(
        &self,
        invocation: CommandInvocation,
    ) -> Result<(CommandHandle, Vec<MessageKind>), SupervisorError> {
        let handle = self.start_command(invocation)?;
        let output = self.collect_dispatch(&handle.plugin_id, &handle.instance_id)?;
        Ok((handle, output))
    }

    pub fn send_ui_event(
        &self,
        plugin_id: &str,
        instance_id: &str,
        event: UiEvent,
    ) -> Result<Vec<MessageKind>, SupervisorError> {
        let state = self
            .plugin_state(plugin_id)?
            .ok_or_else(|| SupervisorError::PluginNotActive(plugin_id.into()))?;
        let mut state = state.lock().map_err(|_| SupervisorError::LockPoisoned)?;
        let (generation_id, command_id) = state
            .commands
            .get(instance_id)
            .map(|command| (command.generation, command.invocation.command_id.clone()))
            .ok_or_else(|| SupervisorError::CommandNotFound(instance_id.into()))?;
        let generation = state
            .generation_mut(generation_id)
            .ok_or_else(|| SupervisorError::PluginNotActive(plugin_id.into()))?;
        let request_id = format!("event-{instance_id}-{}", self.clock.now().as_nanos());
        generation.runner.send(&Envelope::new(
            plugin_id,
            &command_id,
            instance_id,
            &request_id,
            MessageKind::UiEvent(event),
        ))?;
        collect_dispatch_from_runner(
            generation.runner.as_mut(),
            plugin_id,
            instance_id,
            &request_id,
        )
    }

    pub fn respond_to_capability(
        &self,
        plugin_id: &str,
        instance_id: &str,
        request_id: &str,
        response: CapabilityResponse,
    ) -> Result<Vec<MessageKind>, SupervisorError> {
        let state = self
            .plugin_state(plugin_id)?
            .ok_or_else(|| SupervisorError::PluginNotActive(plugin_id.into()))?;
        let mut state = state.lock().map_err(|_| SupervisorError::LockPoisoned)?;
        let (generation_id, command_id) = state
            .commands
            .get(instance_id)
            .map(|command| (command.generation, command.invocation.command_id.clone()))
            .ok_or_else(|| SupervisorError::CommandNotFound(instance_id.into()))?;
        let generation = state
            .generation_mut(generation_id)
            .ok_or_else(|| SupervisorError::PluginNotActive(plugin_id.into()))?;
        generation.runner.send(&Envelope::new(
            plugin_id,
            &command_id,
            instance_id,
            request_id,
            MessageKind::CapabilityResponse(response),
        ))?;
        collect_dispatch_from_runner(
            generation.runner.as_mut(),
            plugin_id,
            instance_id,
            request_id,
        )
    }

    pub fn cancel(&self, plugin_id: &str, instance_id: &str) -> Result<(), SupervisorError> {
        let state = self
            .plugin_state(plugin_id)?
            .ok_or_else(|| SupervisorError::PluginNotActive(plugin_id.into()))?;
        let mut state = state.lock().map_err(|_| SupervisorError::LockPoisoned)?;
        let generation_id = state
            .commands
            .get(instance_id)
            .ok_or_else(|| SupervisorError::CommandNotFound(instance_id.into()))?
            .generation;
        let generation = state
            .generation_mut(generation_id)
            .ok_or_else(|| SupervisorError::PluginNotActive(plugin_id.into()))?;
        generation.runner.send(&Envelope::new(
            plugin_id,
            "__cancel",
            instance_id,
            format!("cancel-{instance_id}"),
            MessageKind::Cancel,
        ))?;
        if let Some(command) = state.commands.get_mut(instance_id) {
            command.status = CommandStatus::Cancelled;
        }
        state.commands.remove(instance_id);
        state.retire_unused();
        Ok(())
    }

    pub fn cancel_and_collect(
        &self,
        plugin_id: &str,
        instance_id: &str,
    ) -> Result<Vec<MessageKind>, SupervisorError> {
        let state = self
            .plugin_state(plugin_id)?
            .ok_or_else(|| SupervisorError::PluginNotActive(plugin_id.into()))?;
        let mut state = state.lock().map_err(|_| SupervisorError::LockPoisoned)?;
        let generation_id = state
            .commands
            .get(instance_id)
            .ok_or_else(|| SupervisorError::CommandNotFound(instance_id.into()))?
            .generation;
        let request_id = format!("cancel-{instance_id}");
        let generation = state
            .generation_mut(generation_id)
            .ok_or_else(|| SupervisorError::PluginNotActive(plugin_id.into()))?;
        generation.runner.send(&Envelope::new(
            plugin_id,
            "__cancel",
            instance_id,
            &request_id,
            MessageKind::Cancel,
        ))?;
        let output = collect_dispatch_from_runner(
            generation.runner.as_mut(),
            plugin_id,
            instance_id,
            &request_id,
        )?;
        state.commands.remove(instance_id);
        state.retire_unused();
        Ok(output)
    }

    pub fn mark_write_started(
        &self,
        plugin_id: &str,
        instance_id: &str,
    ) -> Result<(), SupervisorError> {
        let state = self
            .plugin_state(plugin_id)?
            .ok_or_else(|| SupervisorError::PluginNotActive(plugin_id.into()))?;
        let mut state = state.lock().map_err(|_| SupervisorError::LockPoisoned)?;
        if state.writes_frozen {
            return Err(SupervisorError::WritesFrozen);
        }
        let command = state
            .commands
            .get_mut(instance_id)
            .ok_or_else(|| SupervisorError::CommandNotFound(instance_id.into()))?;
        command.incomplete_write = true;
        Ok(())
    }

    pub fn mark_write_finished(
        &self,
        plugin_id: &str,
        instance_id: &str,
    ) -> Result<(), SupervisorError> {
        self.with_command_mut(plugin_id, instance_id, |command| {
            command.incomplete_write = false;
        })
    }

    pub fn command_status(
        &self,
        plugin_id: &str,
        instance_id: &str,
    ) -> Result<CommandStatus, SupervisorError> {
        let state = self
            .plugin_state(plugin_id)?
            .ok_or_else(|| SupervisorError::PluginNotActive(plugin_id.into()))?;
        let state = state.lock().map_err(|_| SupervisorError::LockPoisoned)?;
        state
            .commands
            .get(instance_id)
            .map(|command| command.status)
            .ok_or_else(|| SupervisorError::CommandNotFound(instance_id.into()))
    }

    pub fn record_termination(
        &self,
        plugin_id: &str,
        command_id: &str,
        termination: Termination,
    ) -> Result<RecoveryReport, SupervisorError> {
        if termination.opens_breaker() {
            self.record_breaker_failure(plugin_id, command_id)?;
        }
        let Some(state) = self.plugin_state(plugin_id)? else {
            return Ok(RecoveryReport {
                restarted: false,
                recovered_instances: Vec::new(),
                outcome_unknown_instances: Vec::new(),
            });
        };

        let (package, limits, generation_id, restart_attempts, replays, unknown) = {
            let mut state = state.lock().map_err(|_| SupervisorError::LockPoisoned)?;
            let Some(mut generation) = state.active.take() else {
                return Ok(RecoveryReport {
                    restarted: false,
                    recovered_instances: Vec::new(),
                    outcome_unknown_instances: Vec::new(),
                });
            };
            generation.runner.stop();
            let generation_id = generation.id;
            let mut replays = Vec::new();
            let mut unknown = Vec::new();
            for command in state
                .commands
                .values_mut()
                .filter(|command| command.generation == generation_id)
            {
                if command.incomplete_write {
                    command.status = CommandStatus::OutcomeUnknown;
                    unknown.push(command.invocation.instance_id.clone());
                } else if command.invocation.restartable
                    && termination.unexpected()
                    && !self.command_disabled(plugin_id, &command.invocation.command_id)
                {
                    command.status = CommandStatus::Recovering;
                    replays.push(command.invocation.clone());
                } else {
                    command.status = CommandStatus::Failed;
                }
            }
            (
                Arc::clone(&generation.package),
                generation.limits.clone(),
                generation_id,
                generation.restart_attempts,
                replays,
                unknown,
            )
        };

        if !termination.unexpected() || restart_attempts >= 1 {
            return Ok(RecoveryReport {
                restarted: false,
                recovered_instances: Vec::new(),
                outcome_unknown_instances: unknown,
            });
        }
        let mut runner = match self.launcher.launch(&package, &limits) {
            Ok(runner) => runner,
            Err(error) => {
                self.note_startup_failure(plugin_id)?;
                return Err(error);
            }
        };
        verify_health(runner.as_mut(), plugin_id)?;
        let now = self.clock.now();
        let mut state = state.lock().map_err(|_| SupervisorError::LockPoisoned)?;
        state.active = Some(RunnerGeneration {
            id: generation_id,
            package,
            runner,
            tracker: LimitTracker::new(limits.clone()),
            limits,
            last_used: now,
            restart_attempts: restart_attempts + 1,
        });
        let mut recovered = Vec::new();
        for invocation in replays {
            let envelope = Envelope::new(
                plugin_id,
                &invocation.command_id,
                &invocation.instance_id,
                format!("recover-{}", invocation.instance_id),
                MessageKind::Start(invocation.start.clone()),
            );
            let result = state
                .active
                .as_mut()
                .expect("active generation was installed")
                .runner
                .send(&envelope);
            if let Some(command) = state.commands.get_mut(&invocation.instance_id) {
                if result.is_ok() {
                    command.status = CommandStatus::Running;
                    recovered.push(invocation.instance_id);
                } else {
                    command.status = CommandStatus::Failed;
                }
            }
            result?;
        }
        Ok(RecoveryReport {
            restarted: true,
            recovered_instances: recovered,
            outcome_unknown_instances: unknown,
        })
    }

    pub fn recover_command(
        &self,
        plugin_id: &str,
        instance_id: &str,
    ) -> Result<(), SupervisorError> {
        let state = self
            .plugin_state(plugin_id)?
            .ok_or_else(|| SupervisorError::PluginNotActive(plugin_id.into()))?;
        let mut state = state.lock().map_err(|_| SupervisorError::LockPoisoned)?;
        let command = state
            .commands
            .get(instance_id)
            .ok_or_else(|| SupervisorError::CommandNotFound(instance_id.into()))?;
        if command.status == CommandStatus::OutcomeUnknown || command.incomplete_write {
            return Err(SupervisorError::OutcomeUnknown);
        }
        let invocation = command.invocation.clone();
        let generation_id = state
            .active
            .as_ref()
            .ok_or_else(|| SupervisorError::PluginNotActive(plugin_id.into()))?
            .id;
        state
            .active
            .as_mut()
            .expect("active generation exists")
            .runner
            .send(&Envelope::new(
                plugin_id,
                &invocation.command_id,
                instance_id,
                format!("manual-recover-{instance_id}"),
                MessageKind::Start(invocation.start),
            ))?;
        if let Some(command) = state.commands.get_mut(instance_id) {
            command.status = CommandStatus::Running;
            command.generation = generation_id;
        }
        self.reset_command_breaker(plugin_id, &invocation.command_id);
        Ok(())
    }

    pub fn stop_plugin(&self, plugin_id: &str) -> Result<(), SupervisorError> {
        let Some(state) = self.plugin_state(plugin_id)? else {
            return Ok(());
        };
        let mut state = state.lock().map_err(|_| SupervisorError::LockPoisoned)?;
        if let Some(mut active) = state.active.take() {
            active.runner.stop();
        }
        for generation in &mut state.retiring {
            generation.runner.stop();
        }
        state.retiring.clear();
        state.commands.clear();
        Ok(())
    }

    pub fn set_resident(&self, plugin_id: &str, resident: bool) -> Result<(), SupervisorError> {
        let state = self.plugin_state_or_insert(plugin_id)?;
        state
            .lock()
            .map_err(|_| SupervisorError::LockPoisoned)?
            .resident = resident;
        Ok(())
    }

    pub fn freeze_writes(&self, plugin_id: &str) -> Result<(), SupervisorError> {
        let state = self.plugin_state_or_insert(plugin_id)?;
        state
            .lock()
            .map_err(|_| SupervisorError::LockPoisoned)?
            .writes_frozen = true;
        Ok(())
    }

    pub fn unfreeze_writes(&self, plugin_id: &str) -> Result<(), SupervisorError> {
        let state = self.plugin_state_or_insert(plugin_id)?;
        state
            .lock()
            .map_err(|_| SupervisorError::LockPoisoned)?
            .writes_frozen = false;
        Ok(())
    }

    pub fn reap_idle(&self) {
        let now = self.clock.now();
        let states = self
            .plugins
            .read()
            .map(|plugins| plugins.values().cloned().collect::<Vec<_>>())
            .unwrap_or_default();
        for state in states {
            let Ok(mut state) = state.lock() else {
                continue;
            };
            if state.resident || !state.commands.is_empty() {
                continue;
            }
            if let Some(active) = state.active.as_mut() {
                if now.saturating_sub(active.last_used) >= active.limits.idle_timeout {
                    active.runner.stop();
                    state.active = None;
                }
            }
            for generation in &mut state.retiring {
                generation.runner.stop();
            }
            state.retiring.clear();
        }
    }

    pub fn can_schedule_background(&self, plugin_id: &str, command_id: &str) -> bool {
        let now = self.clock.now();
        let key = CommandKey {
            plugin_id: plugin_id.into(),
            command_id: command_id.into(),
        };
        let Ok(mut schedules) = self.background_runs.lock() else {
            return false;
        };
        let allowed = schedules.get(&key).is_none_or(|previous| {
            now.saturating_sub(*previous) >= RuntimeLimits::default().minimum_background_interval
        });
        if allowed {
            schedules.insert(key, now);
        }
        allowed
    }

    pub fn command_disabled(&self, plugin_id: &str, command_id: &str) -> bool {
        let key = CommandKey {
            plugin_id: plugin_id.into(),
            command_id: command_id.into(),
        };
        self.breakers
            .lock()
            .ok()
            .and_then(|breakers| breakers.get(&key).map(|breaker| breaker.open))
            .unwrap_or(false)
    }

    pub fn reset_command_breaker(&self, plugin_id: &str, command_id: &str) {
        let key = CommandKey {
            plugin_id: plugin_id.into(),
            command_id: command_id.into(),
        };
        if let Ok(mut breakers) = self.breakers.lock() {
            breakers.entry(key).or_default().reset();
        }
    }

    pub fn begin_host_request(
        &self,
        plugin_id: &str,
        background: bool,
    ) -> Result<(), SupervisorError> {
        self.with_active_generation(plugin_id, |generation| {
            generation.tracker.begin_host_request(background)?;
            Ok(())
        })
    }

    pub fn end_host_request(
        &self,
        plugin_id: &str,
        background: bool,
    ) -> Result<(), SupervisorError> {
        self.with_active_generation(plugin_id, |generation| {
            generation.tracker.end_host_request(background);
            Ok(())
        })
    }

    pub fn record_metric(
        &self,
        plugin_id: &str,
        metric: &ResourceMetric,
    ) -> Result<(), SupervisorError> {
        let now = self.clock.now();
        self.with_active_generation(plugin_id, |generation| {
            generation.tracker.record_metric(now, metric)?;
            Ok(())
        })
    }

    fn with_active_generation<T>(
        &self,
        plugin_id: &str,
        operation: impl FnOnce(&mut RunnerGeneration) -> Result<T, SupervisorError>,
    ) -> Result<T, SupervisorError> {
        let state = self
            .plugin_state(plugin_id)?
            .ok_or_else(|| SupervisorError::PluginNotActive(plugin_id.into()))?;
        let mut state = state.lock().map_err(|_| SupervisorError::LockPoisoned)?;
        operation(
            state
                .active
                .as_mut()
                .ok_or_else(|| SupervisorError::PluginNotActive(plugin_id.into()))?,
        )
    }

    fn collect_dispatch(
        &self,
        plugin_id: &str,
        instance_id: &str,
    ) -> Result<Vec<MessageKind>, SupervisorError> {
        let state = self
            .plugin_state(plugin_id)?
            .ok_or_else(|| SupervisorError::PluginNotActive(plugin_id.into()))?;
        let mut state = state.lock().map_err(|_| SupervisorError::LockPoisoned)?;
        let (generation_id, request_id) = state
            .commands
            .get(instance_id)
            .map(|command| {
                (
                    command.generation,
                    format!("start-{}", command.invocation.instance_id),
                )
            })
            .ok_or_else(|| SupervisorError::CommandNotFound(instance_id.into()))?;
        let generation = state
            .generation_mut(generation_id)
            .ok_or_else(|| SupervisorError::PluginNotActive(plugin_id.into()))?;
        collect_dispatch_from_runner(
            generation.runner.as_mut(),
            plugin_id,
            instance_id,
            &request_id,
        )
    }

    fn with_command_mut(
        &self,
        plugin_id: &str,
        instance_id: &str,
        operation: impl FnOnce(&mut CommandState),
    ) -> Result<(), SupervisorError> {
        let state = self
            .plugin_state(plugin_id)?
            .ok_or_else(|| SupervisorError::PluginNotActive(plugin_id.into()))?;
        let mut state = state.lock().map_err(|_| SupervisorError::LockPoisoned)?;
        let command = state
            .commands
            .get_mut(instance_id)
            .ok_or_else(|| SupervisorError::CommandNotFound(instance_id.into()))?;
        operation(command);
        Ok(())
    }

    fn record_breaker_failure(
        &self,
        plugin_id: &str,
        command_id: &str,
    ) -> Result<(), SupervisorError> {
        let key = CommandKey {
            plugin_id: plugin_id.into(),
            command_id: command_id.into(),
        };
        self.breakers
            .lock()
            .map_err(|_| SupervisorError::LockPoisoned)?
            .entry(key)
            .or_default()
            .record(self.clock.now());
        Ok(())
    }

    fn note_startup_failure(&self, plugin_id: &str) -> Result<(), SupervisorError> {
        let state = self.plugin_state_or_insert(plugin_id)?;
        let mut state = state.lock().map_err(|_| SupervisorError::LockPoisoned)?;
        state.startup_failures = state.startup_failures.saturating_add(1);
        if state.startup_failures >= STARTUP_FAILURES_TO_DISABLE {
            state.disabled = true;
        }
        Ok(())
    }

    fn plugin_state(
        &self,
        plugin_id: &str,
    ) -> Result<Option<Arc<Mutex<PluginState>>>, SupervisorError> {
        Ok(self
            .plugins
            .read()
            .map_err(|_| SupervisorError::LockPoisoned)?
            .get(plugin_id)
            .cloned())
    }

    fn plugin_state_or_insert(
        &self,
        plugin_id: &str,
    ) -> Result<Arc<Mutex<PluginState>>, SupervisorError> {
        if let Some(state) = self.plugin_state(plugin_id)? {
            return Ok(state);
        }
        let mut plugins = self
            .plugins
            .write()
            .map_err(|_| SupervisorError::LockPoisoned)?;
        Ok(Arc::clone(plugins.entry(plugin_id.into()).or_insert_with(
            || Arc::new(Mutex::new(PluginState::default())),
        )))
    }
}

fn verify_health(runner: &mut dyn ManagedRunner, plugin_id: &str) -> Result<(), SupervisorError> {
    runner.send(&Envelope::new(
        plugin_id,
        "__health",
        "supervisor",
        "health",
        MessageKind::Health,
    ))?;
    let response = runner.receive()?;
    if matches!(response.message, MessageKind::Health) && runner.is_running()? {
        Ok(())
    } else {
        Err(SupervisorError::Runner(
            "Runner failed its activation health check".into(),
        ))
    }
}

fn collect_dispatch_from_runner(
    runner: &mut dyn ManagedRunner,
    plugin_id: &str,
    instance_id: &str,
    request_id: &str,
) -> Result<Vec<MessageKind>, SupervisorError> {
    let mut output = Vec::new();
    for _ in 0..MAX_DISPATCH_MESSAGES {
        let envelope = runner.receive()?;
        if envelope.plugin_id != plugin_id
            || envelope.instance_id != instance_id
            || envelope.request_id != request_id
        {
            return Err(SupervisorError::Protocol(
                "Runner response identity does not match the dispatch".into(),
            ));
        }
        if matches!(envelope.message, MessageKind::DispatchComplete) {
            return Ok(output);
        }
        output.push(envelope.message);
    }
    Err(SupervisorError::Protocol(format!(
        "Runner emitted more than {MAX_DISPATCH_MESSAGES} messages for one dispatch"
    )))
}

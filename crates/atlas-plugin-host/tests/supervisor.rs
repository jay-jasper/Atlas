use atlas_plugin_host::{
    Clock, CommandInvocation, CommandStatus, ManagedRunner, PluginSupervisor, RunnerLauncher,
    RuntimeLimits, SupervisorError, Termination,
};
use atlas_plugin_package::{
    sha256_digest, verify_archive, IntegrityDocument, IntegrityFile, PackageLimits,
    PluginManifestV2, RuntimeKind, TrustedKeyStore, VerifiedPackage,
};
use atlas_plugin_protocol::{CommandStart, Envelope, MessageKind};
use std::collections::BTreeMap;
use std::io::{Cursor, Write};
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Barrier, Mutex};
use std::time::Duration;
use zip::write::SimpleFileOptions;

#[derive(Clone, Default)]
struct TestClock(Arc<AtomicU64>);

impl TestClock {
    fn advance(&self, duration: Duration) {
        self.0
            .fetch_add(duration.as_millis() as u64, Ordering::SeqCst);
    }
}

impl Clock for TestClock {
    fn now(&self) -> Duration {
        Duration::from_millis(self.0.load(Ordering::SeqCst))
    }
}

#[derive(Default)]
struct FakeRunner {
    sent: Arc<Mutex<Vec<Envelope>>>,
    stops: Arc<AtomicUsize>,
    running: bool,
}

impl ManagedRunner for FakeRunner {
    fn send(&mut self, envelope: &Envelope) -> Result<(), SupervisorError> {
        self.sent.lock().unwrap().push(envelope.clone());
        Ok(())
    }

    fn receive(&mut self) -> Result<Envelope, SupervisorError> {
        Ok(Envelope::new(
            "fixture",
            "__health",
            "runner",
            "health",
            MessageKind::Health,
        ))
    }

    fn is_running(&mut self) -> Result<bool, SupervisorError> {
        Ok(self.running)
    }

    fn stop(&mut self) {
        self.running = false;
        self.stops.fetch_add(1, Ordering::SeqCst);
    }
}

struct FakeLauncher {
    launches: Arc<AtomicUsize>,
    stops: Arc<AtomicUsize>,
    sent: Arc<Mutex<Vec<Envelope>>>,
    barrier: Option<Arc<Barrier>>,
}

impl FakeLauncher {
    fn new() -> Self {
        Self {
            launches: Arc::new(AtomicUsize::new(0)),
            stops: Arc::new(AtomicUsize::new(0)),
            sent: Arc::new(Mutex::new(Vec::new())),
            barrier: None,
        }
    }
}

impl RunnerLauncher for FakeLauncher {
    fn launch(
        &self,
        _package: &VerifiedPackage,
        _limits: &RuntimeLimits,
    ) -> Result<Box<dyn ManagedRunner>, SupervisorError> {
        self.launches.fetch_add(1, Ordering::SeqCst);
        if let Some(barrier) = &self.barrier {
            barrier.wait();
        }
        Ok(Box::new(FakeRunner {
            sent: Arc::clone(&self.sent),
            stops: Arc::clone(&self.stops),
            running: true,
        }))
    }
}

fn invocation(plugin_id: &str, instance_id: &str, restartable: bool) -> CommandInvocation {
    CommandInvocation {
        plugin_id: plugin_id.into(),
        command_id: "main".into(),
        instance_id: instance_id.into(),
        start: CommandStart {
            arguments: vec![],
            environment: vec![],
        },
        restartable,
        background: false,
    }
}

#[test]
fn third_failure_in_ten_minutes_opens_command_breaker() {
    let clock = TestClock::default();
    let launcher = Arc::new(FakeLauncher::new());
    let supervisor = PluginSupervisor::new(launcher, Arc::new(clock.clone()));

    for _ in 0..3 {
        supervisor
            .record_termination("plugin", "main", Termination::Limit)
            .unwrap();
        clock.advance(Duration::from_secs(60));
    }

    assert!(supervisor.command_disabled("plugin", "main"));
    supervisor.reset_command_breaker("plugin", "main");
    assert!(!supervisor.command_disabled("plugin", "main"));
}

#[test]
fn restartable_commands_recover_but_incomplete_writes_do_not_replay() {
    let clock = TestClock::default();
    let launcher = Arc::new(FakeLauncher::new());
    let launches = Arc::clone(&launcher.launches);
    let sent = Arc::clone(&launcher.sent);
    let supervisor = PluginSupervisor::new(launcher, Arc::new(clock));
    supervisor
        .activate_generation(package("dev.example.recovery", "1.0.0"))
        .unwrap();
    supervisor
        .start_command(invocation("dev.example.recovery", "safe", true))
        .unwrap();
    supervisor
        .start_command(invocation("dev.example.recovery", "write", true))
        .unwrap();
    supervisor
        .mark_write_started("dev.example.recovery", "write")
        .unwrap();

    supervisor
        .record_termination("dev.example.recovery", "main", Termination::Crash)
        .unwrap();

    assert_eq!(launches.load(Ordering::SeqCst), 2);
    assert_eq!(
        supervisor
            .command_status("dev.example.recovery", "safe")
            .unwrap(),
        CommandStatus::Running
    );
    assert_eq!(
        supervisor
            .command_status("dev.example.recovery", "write")
            .unwrap(),
        CommandStatus::OutcomeUnknown
    );
    let safe_replays = sent
        .lock()
        .unwrap()
        .iter()
        .filter(|envelope| {
            envelope.instance_id == "safe" && matches!(envelope.message, MessageKind::Start(_))
        })
        .count();
    assert_eq!(safe_replays, 2);
}

#[test]
fn generations_idle_exit_and_background_schedule_are_enforced() {
    let clock = TestClock::default();
    let launcher = Arc::new(FakeLauncher::new());
    let stops = Arc::clone(&launcher.stops);
    let supervisor = PluginSupervisor::new(launcher, Arc::new(clock.clone()));

    let generation_one = supervisor
        .activate_generation(package("dev.example.generation", "1.0.0"))
        .unwrap();
    supervisor
        .start_command(invocation("dev.example.generation", "old", false))
        .unwrap();
    let generation_two = supervisor
        .activate_generation(package("dev.example.generation", "2.0.0"))
        .unwrap();
    let new = supervisor
        .start_command(invocation("dev.example.generation", "new", false))
        .unwrap();
    assert_ne!(generation_one, generation_two);
    assert_eq!(new.generation, generation_two);

    assert!(supervisor.can_schedule_background("dev.example.generation", "refresh"));
    assert!(!supervisor.can_schedule_background("dev.example.generation", "refresh"));
    clock.advance(Duration::from_secs(60));
    assert!(supervisor.can_schedule_background("dev.example.generation", "refresh"));

    supervisor.cancel("dev.example.generation", "old").unwrap();
    supervisor.cancel("dev.example.generation", "new").unwrap();
    clock.advance(Duration::from_secs(301));
    supervisor.reap_idle();
    assert!(stops.load(Ordering::SeqCst) >= 2);
}

#[test]
fn twenty_plugins_launch_without_a_global_dispatch_lock() {
    let barrier = Arc::new(Barrier::new(20));
    let launcher = Arc::new(FakeLauncher {
        launches: Arc::new(AtomicUsize::new(0)),
        stops: Arc::new(AtomicUsize::new(0)),
        sent: Arc::new(Mutex::new(Vec::new())),
        barrier: Some(Arc::clone(&barrier)),
    });
    let supervisor = Arc::new(PluginSupervisor::new(
        launcher,
        Arc::new(TestClock::default()),
    ));
    let mut threads = Vec::new();
    for index in 0..20 {
        let supervisor = Arc::clone(&supervisor);
        threads.push(std::thread::spawn(move || {
            supervisor
                .activate_generation(package(&format!("dev.example.concurrent-{index}"), "1.0.0"))
                .unwrap();
        }));
    }
    for thread in threads {
        thread.join().unwrap();
    }
}

#[test]
fn package_migration_freezes_new_writes_until_activation_finishes() {
    let launcher = Arc::new(FakeLauncher::new());
    let supervisor = PluginSupervisor::new(launcher, Arc::new(TestClock::default()));
    supervisor
        .activate_generation(package("dev.example.freeze", "1.0.0"))
        .unwrap();
    supervisor
        .start_command(invocation("dev.example.freeze", "writer", false))
        .unwrap();

    supervisor.freeze_writes("dev.example.freeze").unwrap();
    assert!(matches!(
        supervisor.mark_write_started("dev.example.freeze", "writer"),
        Err(SupervisorError::WritesFrozen)
    ));
    supervisor.unfreeze_writes("dev.example.freeze").unwrap();
    supervisor
        .mark_write_started("dev.example.freeze", "writer")
        .unwrap();
}

fn package(plugin_id: &str, version: &str) -> Arc<VerifiedPackage> {
    let manifest = PluginManifestV2 {
        manifest_version: 2,
        id: plugin_id.into(),
        name: plugin_id.into(),
        version: version.into(),
        publisher: "Example".into(),
        runtime: RuntimeKind::Wasm,
        entrypoint: "payload/main.wasm".into(),
        storage_schema: 1,
        capabilities: vec![],
        trust: None,
    };
    let mut files = BTreeMap::from([
        (
            "plugin.toml".to_string(),
            toml::to_string(&manifest).unwrap().into_bytes(),
        ),
        (
            "permissions.json".to_string(),
            serde_json::to_vec(&manifest.capabilities).unwrap(),
        ),
        ("payload/main.wasm".to_string(), b"fixture".to_vec()),
    ]);
    let records = files
        .iter()
        .map(|(path, bytes)| IntegrityFile {
            path: path.clone(),
            length: bytes.len() as u64,
            sha256: sha256_digest(bytes)
                .iter()
                .map(|byte| format!("{byte:02x}"))
                .collect(),
        })
        .collect();
    files.insert(
        "integrity.json".into(),
        serde_json::to_vec(&IntegrityDocument::new(records).unwrap()).unwrap(),
    );
    let mut archive = Cursor::new(Vec::new());
    {
        let mut writer = zip::ZipWriter::new(&mut archive);
        for (path, bytes) in files {
            writer
                .start_file(path, SimpleFileOptions::default())
                .unwrap();
            writer.write_all(&bytes).unwrap();
        }
        writer.finish().unwrap();
    }
    Arc::new(
        verify_archive(
            Cursor::new(archive.into_inner()),
            &PackageLimits::default(),
            &TrustedKeyStore::new(),
        )
        .unwrap(),
    )
}

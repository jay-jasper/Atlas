use std::sync::mpsc::{self, Sender};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use rquickjs::{CatchResultExt, Context, Function, Runtime};

pub const DEFAULT_MEMORY_LIMIT: usize = 32 * 1024 * 1024;
pub const DEFAULT_STACK_LIMIT: usize = 512 * 1024;
pub const DEFAULT_CPU_LIMIT: Duration = Duration::from_millis(200);

#[derive(Debug, Clone, Copy)]
pub struct JsLimits {
    pub max_memory_bytes: usize,
    pub max_stack_bytes: usize,
    pub cpu_limit: Duration,
}

impl Default for JsLimits {
    fn default() -> Self {
        Self {
            max_memory_bytes: DEFAULT_MEMORY_LIMIT,
            max_stack_bytes: DEFAULT_STACK_LIMIT,
            cpu_limit: DEFAULT_CPU_LIMIT,
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum JsError {
    #[error("javascript runtime failed: {0}")]
    Runtime(String),
    #[error("javascript plugin must export an object")]
    MissingExport,
    #[error("javascript plugin worker stopped")]
    WorkerStopped,
    #[error("javascript promise cannot make progress")]
    PromisePending,
    #[error("javascript call exceeded its deadline")]
    Timeout,
    #[error("unhandled javascript promise rejection: {0}")]
    UnhandledRejection(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum JsCallStatus {
    Complete(String),
    HostRequests(Vec<String>),
    Pending,
}

/// Engine seam keeps the host independent from a particular JS implementation.
pub trait JsEngine {
    fn eval(&mut self, source: &str) -> Result<(), JsError>;
    fn call(&mut self, function: &str, args_json: &str) -> Result<String, JsError>;
    fn set_memory_limit(&mut self, bytes: usize);
    fn set_stack_limit(&mut self, bytes: usize);
    fn set_cpu_limit(&mut self, duration: Duration);
}

/// One isolated QuickJS heap per plugin. QuickJS exposes no filesystem,
/// process, or network APIs; capabilities must be injected explicitly by host code.
pub struct QuickJsEngine {
    runtime: Runtime,
    context: Context,
    deadline: Arc<Mutex<Instant>>,
    cpu_limit: Duration,
    host_requests: Arc<Mutex<Vec<String>>>,
}

enum WorkerCommand {
    HasFunction {
        name: String,
        reply: Sender<Result<bool, JsError>>,
    },
    Call {
        function: String,
        args_json: String,
        reply: Sender<Result<JsCallStatus, JsError>>,
    },
    ResumeHost {
        response_json: String,
        reply: Sender<Result<JsCallStatus, JsError>>,
    },
}

/// Sendable handle to a QuickJS heap confined to its own worker thread.
pub struct JsPlugin {
    commands: Sender<WorkerCommand>,
}

impl JsPlugin {
    pub fn spawn(source: &str) -> Result<Self, JsError> {
        Self::spawn_with_limits(source, JsLimits::default())
    }

    pub fn spawn_with_limits(source: &str, limits: JsLimits) -> Result<Self, JsError> {
        let (commands, receiver) = mpsc::channel();
        let (ready_tx, ready_rx) = mpsc::sync_channel(1);
        let source = source.to_owned();
        thread::Builder::new()
            .name("atlas-plugin-js".into())
            .spawn(move || {
                let mut engine = match QuickJsEngine::new().and_then(|mut engine| {
                    engine.set_memory_limit(limits.max_memory_bytes);
                    engine.set_stack_limit(limits.max_stack_bytes);
                    engine.set_cpu_limit(limits.cpu_limit);
                    engine.eval(&source)?;
                    Ok(engine)
                }) {
                    Ok(engine) => {
                        let _ = ready_tx.send(Ok(()));
                        engine
                    }
                    Err(error) => {
                        let _ = ready_tx.send(Err(error));
                        return;
                    }
                };
                while let Ok(command) = receiver.recv() {
                    match command {
                        WorkerCommand::HasFunction { name, reply } => {
                            let _ = reply.send(engine.has_function(&name));
                        }
                        WorkerCommand::Call {
                            function,
                            args_json,
                            reply,
                        } => {
                            let _ = reply.send(engine.call_status(&function, &args_json));
                        }
                        WorkerCommand::ResumeHost {
                            response_json,
                            reply,
                        } => {
                            let _ = reply.send(engine.resume_host(&response_json));
                        }
                    }
                }
            })
            .map_err(runtime_error)?;
        ready_rx.recv().map_err(|_| JsError::WorkerStopped)??;
        Ok(Self { commands })
    }

    pub fn has_function(&self, name: &str) -> Result<bool, JsError> {
        let (reply, response) = mpsc::channel();
        self.commands
            .send(WorkerCommand::HasFunction {
                name: name.to_owned(),
                reply,
            })
            .map_err(|_| JsError::WorkerStopped)?;
        response.recv().map_err(|_| JsError::WorkerStopped)?
    }

    pub fn call(&self, function: &str, args_json: &str) -> Result<String, JsError> {
        match self.call_status(function, args_json)? {
            JsCallStatus::Complete(value) => Ok(value),
            JsCallStatus::HostRequests(_) | JsCallStatus::Pending => Err(JsError::PromisePending),
        }
    }

    pub fn call_status(&self, function: &str, args_json: &str) -> Result<JsCallStatus, JsError> {
        let (reply, response) = mpsc::channel();
        self.commands
            .send(WorkerCommand::Call {
                function: function.to_owned(),
                args_json: args_json.to_owned(),
                reply,
            })
            .map_err(|_| JsError::WorkerStopped)?;
        response.recv().map_err(|_| JsError::WorkerStopped)?
    }

    pub fn resume_host(&self, response_json: &str) -> Result<JsCallStatus, JsError> {
        let (reply, response) = mpsc::channel();
        self.commands
            .send(WorkerCommand::ResumeHost {
                response_json: response_json.to_owned(),
                reply,
            })
            .map_err(|_| JsError::WorkerStopped)?;
        response.recv().map_err(|_| JsError::WorkerStopped)?
    }
}

impl QuickJsEngine {
    pub fn new() -> Result<Self, JsError> {
        let runtime = Runtime::new().map_err(runtime_error)?;
        runtime.set_memory_limit(DEFAULT_MEMORY_LIMIT);
        runtime.set_max_stack_size(DEFAULT_STACK_LIMIT);
        let deadline = Arc::new(Mutex::new(Instant::now() + DEFAULT_CPU_LIMIT));
        let interrupt_deadline = deadline.clone();
        runtime.set_interrupt_handler(Some(Box::new(move || {
            Instant::now() >= *interrupt_deadline.lock().expect("deadline lock poisoned")
        })));
        let context = Context::full(&runtime).map_err(runtime_error)?;
        let host_requests = Arc::new(Mutex::new(Vec::new()));
        let host_queue = Arc::clone(&host_requests);
        context
            .with(|ctx| {
                ctx.globals().set(
                    "__atlasHostSend",
                    Function::new(ctx.clone(), move |request: String| {
                        host_queue
                            .lock()
                            .expect("host request queue lock poisoned")
                            .push(request);
                    }),
                )
            })
            .map_err(runtime_error)?;
        Ok(Self {
            runtime,
            context,
            deadline,
            cpu_limit: DEFAULT_CPU_LIMIT,
            host_requests,
        })
    }

    pub fn has_function(&mut self, name: &str) -> Result<bool, JsError> {
        self.reset_deadline();
        let name = serde_json::to_string(name).expect("string serialization cannot fail");
        self.context
            .with(|ctx| {
                ctx.eval::<bool, _>(format!(
                    "typeof globalThis.__atlasPlugin?.[{name}] === 'function'"
                ))
            })
            .map_err(runtime_error)
    }

    fn reset_deadline(&self) {
        *self.deadline.lock().expect("deadline lock poisoned") = Instant::now() + self.cpu_limit;
    }
}

impl JsEngine for QuickJsEngine {
    fn eval(&mut self, source: &str) -> Result<(), JsError> {
        self.reset_deadline();
        self.context
            .with(|ctx| ctx.eval::<(), _>(TIMER_BOOTSTRAP))
            .map_err(runtime_error)?;
        let normalized = if source.contains("export default") {
            source.replacen("export default", "globalThis.__atlasPlugin =", 1)
        } else {
            format!("{source}\nglobalThis.__atlasPlugin = globalThis.atlasPlugin;")
        };
        self.context.with(|ctx| {
            ctx.eval::<(), _>(normalized)
                .catch(&ctx)
                .map_err(|error| JsError::Runtime(error.to_string()))
        })?;
        let present = self
            .context
            .with(|ctx| ctx.eval::<bool, _>("typeof globalThis.__atlasPlugin === 'object'"))
            .map_err(runtime_error)?;
        if present {
            Ok(())
        } else {
            Err(JsError::MissingExport)
        }
    }

    fn call(&mut self, function: &str, args_json: &str) -> Result<String, JsError> {
        match self.call_status(function, args_json)? {
            JsCallStatus::Complete(value) => Ok(value),
            JsCallStatus::HostRequests(_) | JsCallStatus::Pending => Err(JsError::PromisePending),
        }
    }

    fn set_memory_limit(&mut self, bytes: usize) {
        self.runtime.set_memory_limit(bytes);
    }

    fn set_stack_limit(&mut self, bytes: usize) {
        self.runtime.set_max_stack_size(bytes);
    }

    fn set_cpu_limit(&mut self, duration: Duration) {
        self.cpu_limit = duration;
    }
}

impl QuickJsEngine {
    fn call_status(&mut self, function: &str, args_json: &str) -> Result<JsCallStatus, JsError> {
        self.reset_deadline();
        let deadline = Instant::now() + self.cpu_limit;
        let function = serde_json::to_string(function).expect("string serialization cannot fail");
        let args: serde_json::Value =
            serde_json::from_str(args_json).map_err(|error| JsError::Runtime(error.to_string()))?;
        let args = serde_json::to_string(&args).expect("JSON serialization cannot fail");
        let script = format!(
            r#"
            globalThis.__atlasCallState = {{ done: false }};
            try {{
                const result = globalThis.__atlasPlugin[{function}](...{args});
                Promise.resolve(result).then(
                    value => {{ globalThis.__atlasCallState = {{ done: true, ok: true, value }}; }},
                    error => {{ globalThis.__atlasCallState = {{
                        done: true,
                        ok: false,
                        error: String(error?.message ?? error) + "\n" + String(error?.stack ?? "")
                    }}; }}
                );
            }} catch (error) {{
                globalThis.__atlasCallState = {{
                    done: true,
                    ok: false,
                    error: String(error?.message ?? error) + "\n" + String(error?.stack ?? "")
                }};
            }}
            "#
        );
        self.context
            .with(|ctx| ctx.eval::<(), _>(script))
            .map_err(runtime_error)?;
        self.finish_call(deadline)
    }

    fn resume_host(&mut self, response_json: &str) -> Result<JsCallStatus, JsError> {
        self.reset_deadline();
        let response = serde_json::to_string(response_json)
            .expect("response string serialization cannot fail");
        self.context
            .with(|ctx| {
                ctx.eval::<(), _>(format!(
                    "globalThis.__atlasHostReceive(JSON.parse({response}));"
                ))
            })
            .map_err(runtime_error)?;
        self.finish_call(Instant::now() + self.cpu_limit)
    }
}

impl QuickJsEngine {
    fn finish_call(&mut self, deadline: Instant) -> Result<JsCallStatus, JsError> {
        loop {
            if Instant::now() >= deadline {
                return Err(JsError::Timeout);
            }
            while self.runtime.is_job_pending() {
                self.runtime
                    .execute_pending_job()
                    .map_err(|error| JsError::UnhandledRejection(error.to_string()))?;
                if Instant::now() >= deadline {
                    return Err(JsError::Timeout);
                }
            }
            let requests = {
                let mut queue = self
                    .host_requests
                    .lock()
                    .expect("host request queue lock poisoned");
                std::mem::take(&mut *queue)
            };
            if !requests.is_empty() {
                return Ok(JsCallStatus::HostRequests(requests));
            }

            let state = self
                .context
                .with(|ctx| {
                    ctx.eval::<String, _>(
                        "JSON.stringify(globalThis.__atlasCallState ?? { done: false })",
                    )
                })
                .map_err(runtime_error)?;
            let state: serde_json::Value = serde_json::from_str(&state)
                .map_err(|error| JsError::Runtime(error.to_string()))?;
            if state["done"].as_bool() == Some(true) {
                if state["ok"].as_bool() == Some(true) {
                    return serde_json::to_string(
                        state.get("value").unwrap_or(&serde_json::Value::Null),
                    )
                    .map(JsCallStatus::Complete)
                    .map_err(|error| JsError::Runtime(error.to_string()));
                }
                return Err(JsError::UnhandledRejection(
                    state["error"]
                        .as_str()
                        .unwrap_or("unknown rejection")
                        .to_owned(),
                ));
            }

            let timer_state = self
                .context
                .with(|ctx| ctx.eval::<String, _>("JSON.stringify(globalThis.__atlasPumpTimers())"))
                .map_err(runtime_error)?;
            let timer_state: serde_json::Value = serde_json::from_str(&timer_state)
                .map_err(|error| JsError::Runtime(error.to_string()))?;
            if let Some(error) = timer_state["unhandled"].as_str() {
                return Err(JsError::UnhandledRejection(error.to_owned()));
            }
            if timer_state["pending"].as_u64() == Some(0) && !self.runtime.is_job_pending() {
                return Ok(JsCallStatus::Pending);
            }
            let delay = timer_state["nextDelay"].as_u64().unwrap_or(0).min(10);
            if delay > 0 {
                std::thread::sleep(Duration::from_millis(delay));
            }
        }
    }
}

const TIMER_BOOTSTRAP: &str = r#"
if (!globalThis.__atlasTimers) {
    globalThis.global = globalThis;
    globalThis.console ??= {
        log() {}, info() {}, warn() {}, error() {}, debug() {}, trace() {}
    };
    globalThis.performance ??= { now: () => Date.now(), measure() {}, mark() {}, clearMarks() {}, clearMeasures() {} };
    globalThis.queueMicrotask ??= callback => Promise.resolve().then(callback);
    globalThis.IS_REACT_ACT_ENVIRONMENT = true;
    globalThis.__atlasTimers = new Map();
    globalThis.__atlasTimerId = 0;
    globalThis.__atlasUnhandled = [];
    globalThis.setTimeout = (callback, delay = 0, ...args) => {
        if (typeof callback !== "function") throw new TypeError("setTimeout callback must be a function");
        const id = ++globalThis.__atlasTimerId;
        const boundedDelay = Math.max(0, Math.min(Number(delay) || 0, 60_000));
        globalThis.__atlasTimers.set(id, {
            callback,
            args,
            due: Date.now() + boundedDelay
        });
        return id;
    };
    globalThis.clearTimeout = id => globalThis.__atlasTimers.delete(id);
    globalThis.setImmediate = callback => globalThis.setTimeout(callback, 0);
    globalThis.clearImmediate = id => globalThis.clearTimeout(id);
    globalThis.__atlasPumpTimers = () => {
        const now = Date.now();
        for (const [id, timer] of [...globalThis.__atlasTimers]) {
            if (timer.due > now) continue;
            globalThis.__atlasTimers.delete(id);
            try {
                Promise.resolve(timer.callback(...timer.args)).catch(error => {
                    globalThis.__atlasUnhandled.push(
                        `${String(error?.message ?? error)}\n${String(error?.stack ?? "")}`
                    );
                });
            } catch (error) {
                globalThis.__atlasUnhandled.push(
                    `${String(error?.message ?? error)}\n${String(error?.stack ?? "")}`
                );
            }
        }
        const next = [...globalThis.__atlasTimers.values()]
            .reduce((minimum, timer) => Math.min(minimum, Math.max(0, timer.due - Date.now())), Infinity);
        return {
            pending: globalThis.__atlasTimers.size,
            nextDelay: Number.isFinite(next) ? next : 0,
            unhandled: globalThis.__atlasUnhandled.shift()
        };
    };
}
"#;

fn runtime_error(error: impl std::fmt::Display) -> JsError {
    JsError::Runtime(error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn loads_default_export_and_calls_action() {
        let mut engine = QuickJsEngine::new().unwrap();
        engine
            .eval("export default { onAction(id, payload) { return { id, payload }; } };")
            .unwrap();
        assert!(engine.has_function("onAction").unwrap());
        assert_eq!(
            engine
                .call("onAction", r#"["copy",{"value":"hi"}]"#)
                .unwrap(),
            r#"{"id":"copy","payload":{"value":"hi"}}"#
        );
    }

    #[test]
    fn blocks_infinite_loops_with_watchdog() {
        let mut engine = QuickJsEngine::new().unwrap();
        engine.set_cpu_limit(Duration::from_millis(10));
        assert!(engine
            .eval("export default (() => { while (true) {} })()")
            .is_err());
    }

    #[test]
    fn rejects_missing_export() {
        let mut engine = QuickJsEngine::new().unwrap();
        assert!(matches!(
            engine.eval("const value = 1"),
            Err(JsError::MissingExport)
        ));
    }

    #[test]
    fn thread_confined_plugin_handle_is_sendable() {
        let plugin =
            JsPlugin::spawn("export default { onAction(id) { return { action: id }; } };").unwrap();
        let result = std::thread::spawn(move || plugin.call("onAction", r#"["run"]"#).unwrap())
            .join()
            .unwrap();
        assert_eq!(result, r#"{"action":"run"}"#);
    }

    #[test]
    fn pumps_promises_and_host_backed_timers() {
        let plugin = JsPlugin::spawn(
            r#"
            export default {
                async start() {
                    await new Promise(resolve => setTimeout(resolve, 1));
                    return { ready: true };
                }
            };
            "#,
        )
        .unwrap();
        assert_eq!(plugin.call("start", "[]").unwrap(), r#"{"ready":true}"#);
    }

    #[test]
    fn reports_unhandled_rejections() {
        let plugin = JsPlugin::spawn(
            r#"
            export default {
                async start() {
                    throw new Error("fixture rejection");
                }
            };
            "#,
        )
        .unwrap();
        let result = plugin.call("start", "[]");
        assert!(
            matches!(
                &result,
                Err(JsError::UnhandledRejection(message)) if message.contains("fixture rejection")
            ),
            "{result:?}"
        );
    }
}

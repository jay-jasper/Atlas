use std::sync::mpsc::{self, Sender};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use rquickjs::{Context, Runtime};

pub const DEFAULT_MEMORY_LIMIT: usize = 32 * 1024 * 1024;
pub const DEFAULT_STACK_LIMIT: usize = 512 * 1024;
pub const DEFAULT_CPU_LIMIT: Duration = Duration::from_millis(200);

#[derive(Debug, thiserror::Error)]
pub enum JsError {
    #[error("javascript runtime failed: {0}")]
    Runtime(String),
    #[error("javascript plugin must export an object")]
    MissingExport,
    #[error("javascript plugin worker stopped")]
    WorkerStopped,
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
}

enum WorkerCommand {
    HasFunction {
        name: String,
        reply: Sender<Result<bool, JsError>>,
    },
    Call {
        function: String,
        args_json: String,
        reply: Sender<Result<String, JsError>>,
    },
}

/// Sendable handle to a QuickJS heap confined to its own worker thread.
pub struct JsPlugin {
    commands: Sender<WorkerCommand>,
}

impl JsPlugin {
    pub fn spawn(source: &str) -> Result<Self, JsError> {
        let (commands, receiver) = mpsc::channel();
        let (ready_tx, ready_rx) = mpsc::sync_channel(1);
        let source = source.to_owned();
        thread::Builder::new()
            .name("atlas-plugin-js".into())
            .spawn(move || {
                let mut engine = match QuickJsEngine::new().and_then(|mut engine| {
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
                            let _ = reply.send(engine.call(&function, &args_json));
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
        Ok(Self {
            runtime,
            context,
            deadline,
            cpu_limit: DEFAULT_CPU_LIMIT,
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
        let normalized = if source.contains("export default") {
            source.replacen("export default", "globalThis.__atlasPlugin =", 1)
        } else {
            format!("{source}\nglobalThis.__atlasPlugin = globalThis.atlasPlugin;")
        };
        self.context
            .with(|ctx| ctx.eval::<(), _>(normalized))
            .map_err(runtime_error)?;
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
        self.reset_deadline();
        let function = serde_json::to_string(function).expect("string serialization cannot fail");
        let args: serde_json::Value =
            serde_json::from_str(args_json).map_err(|error| JsError::Runtime(error.to_string()))?;
        let args = serde_json::to_string(&args).expect("JSON serialization cannot fail");
        let script = format!("JSON.stringify(globalThis.__atlasPlugin[{function}](...{args}))");
        self.context
            .with(|ctx| ctx.eval::<String, _>(script))
            .map_err(runtime_error)
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
}

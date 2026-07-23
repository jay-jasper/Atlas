use super::{RuntimeAdapter, RuntimeError, RuntimeHealth, UiOutputState, MAX_RUNTIME_OUTPUT_BYTES};
use crate::RunnerLimits;
use atlas_plugin_host::{WasmHost, WasmLimits};
use atlas_plugin_protocol::{CommandStart, MessageKind};
use atlas_ui_schema::UiEvent;
use std::time::Duration;

pub struct WasmAdapter {
    host: WasmHost,
    ui: UiOutputState,
    active: bool,
    stopped: bool,
}

impl WasmAdapter {
    pub fn new(module: &[u8], limits: RunnerLimits) -> Result<Self, RuntimeError> {
        let max_memory_bytes = usize::try_from(limits.max_memory_bytes)
            .map_err(|_| RuntimeError::Load("memory limit is too large".into()))?;
        let host = WasmHost::load_with_limits(
            module,
            WasmLimits {
                max_memory_bytes,
                fuel_per_call: limits.max_cpu_millis.saturating_mul(10_000).max(10_000),
                call_timeout: Duration::from_millis(limits.wall_timeout_millis),
            },
        )
        .map_err(|error| RuntimeError::Load(error.to_string()))?;
        Ok(Self {
            host,
            ui: UiOutputState::default(),
            active: false,
            stopped: false,
        })
    }

    fn call<T: serde::Serialize>(
        &mut self,
        export: &str,
        input: &T,
    ) -> Result<Vec<MessageKind>, RuntimeError> {
        let input =
            serde_json::to_vec(input).map_err(|error| RuntimeError::Call(error.to_string()))?;
        let output = self
            .host
            .call_serialized(export, &input, MAX_RUNTIME_OUTPUT_BYTES)
            .map_err(|error| RuntimeError::Call(error.to_string()))?;
        self.ui.decode(&output)
    }
}

impl RuntimeAdapter for WasmAdapter {
    fn start(&mut self, command: CommandStart) -> Result<Vec<MessageKind>, RuntimeError> {
        if self.stopped {
            return Err(RuntimeError::Stopped);
        }
        if self.active {
            return Err(RuntimeError::AlreadyStarted);
        }
        let messages = self.call("atlas_start", &command)?;
        self.active = true;
        Ok(messages)
    }

    fn event(&mut self, event: UiEvent) -> Result<Vec<MessageKind>, RuntimeError> {
        if !self.active {
            return Err(RuntimeError::NotActive);
        }
        self.call("atlas_event", &event)
    }

    fn cancel(&mut self, instance_id: &str) -> Result<(), RuntimeError> {
        if !self.active {
            return Ok(());
        }
        let result = self
            .call(
                "atlas_cancel",
                &serde_json::json!({ "instanceId": instance_id }),
            )
            .map(|_| ());
        self.active = false;
        self.ui.close();
        result
    }

    fn health(&mut self) -> RuntimeHealth {
        if self.stopped {
            RuntimeHealth::Stopped
        } else {
            RuntimeHealth::Ready
        }
    }

    fn shutdown(&mut self) -> Result<(), RuntimeError> {
        self.active = false;
        self.stopped = true;
        self.ui.close();
        Ok(())
    }
}

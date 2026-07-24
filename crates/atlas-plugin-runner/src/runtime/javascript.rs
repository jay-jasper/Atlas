use super::{RuntimeAdapter, RuntimeError, RuntimeHealth, UiOutputState};
use crate::RunnerLimits;
use atlas_plugin_js::{JsCallStatus, JsLimits, JsPlugin};
use atlas_plugin_protocol::{CapabilityRequest, CapabilityResponse, CommandStart, MessageKind};
use atlas_ui_schema::UiEvent;
use serde::Deserialize;
use std::time::Duration;

pub struct JavascriptAdapter {
    plugin: JsPlugin,
    ui: UiOutputState,
    active: bool,
    stopped: bool,
}

impl JavascriptAdapter {
    pub fn new(source: &str, limits: RunnerLimits) -> Result<Self, RuntimeError> {
        let plugin = JsPlugin::spawn_with_limits(
            source,
            JsLimits {
                max_memory_bytes: usize::try_from(limits.max_memory_bytes)
                    .map_err(|_| RuntimeError::Load("memory limit is too large".into()))?,
                max_stack_bytes: 512 * 1024,
                cpu_limit: Duration::from_millis(limits.max_cpu_millis),
            },
        )
        .map_err(|error| RuntimeError::Load(error.to_string()))?;
        Ok(Self {
            plugin,
            ui: UiOutputState::default(),
            active: false,
            stopped: false,
        })
    }

    fn call(
        &mut self,
        function: &str,
        arguments: serde_json::Value,
    ) -> Result<Vec<MessageKind>, RuntimeError> {
        let status = self
            .plugin
            .call_status(function, &arguments.to_string())
            .map_err(|error| RuntimeError::Call(error.to_string()))?;
        self.decode_status(status)
    }

    fn decode_status(&mut self, status: JsCallStatus) -> Result<Vec<MessageKind>, RuntimeError> {
        match status {
            JsCallStatus::Complete(output) => self.ui.decode(output.as_bytes()),
            JsCallStatus::Pending => Ok(Vec::new()),
            JsCallStatus::HostRequests(requests) => requests
                .into_iter()
                .map(|request| {
                    let request: JsHostRequest = serde_json::from_str(&request)
                        .map_err(|error| RuntimeError::Output(error.to_string()))?;
                    let operation = request
                        .capability
                        .rsplit_once('.')
                        .map_or("perform", |(_, operation)| operation)
                        .to_owned();
                    let resource = request
                        .payload
                        .get("input")
                        .or_else(|| request.payload.get("key"))
                        .and_then(serde_json::Value::as_str)
                        .map(str::to_owned);
                    Ok(MessageKind::CapabilityRequest(CapabilityRequest {
                        request_id: Some(request.request_id),
                        capability: request.capability,
                        operation,
                        resource,
                        payload: serde_json::to_vec(&request.payload)
                            .map_err(|error| RuntimeError::Output(error.to_string()))?,
                    }))
                })
                .collect(),
        }
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct JsHostRequest {
    request_id: String,
    capability: String,
    payload: serde_json::Value,
}

impl RuntimeAdapter for JavascriptAdapter {
    fn start(&mut self, command: CommandStart) -> Result<Vec<MessageKind>, RuntimeError> {
        if self.stopped {
            return Err(RuntimeError::Stopped);
        }
        if self.active {
            return Err(RuntimeError::AlreadyStarted);
        }
        if !self
            .plugin
            .has_function("start")
            .map_err(|error| RuntimeError::Call(error.to_string()))?
        {
            return Err(RuntimeError::Load(
                "JavaScript plugin does not export start".into(),
            ));
        }
        let messages = self.call(
            "start",
            serde_json::json!([{
                "arguments": command.arguments,
                "environment": command.environment,
            }]),
        )?;
        self.active = true;
        Ok(messages)
    }

    fn event(&mut self, event: UiEvent) -> Result<Vec<MessageKind>, RuntimeError> {
        if !self.active {
            return Err(RuntimeError::NotActive);
        }
        if !self
            .plugin
            .has_function("onEvent")
            .map_err(|error| RuntimeError::Call(error.to_string()))?
        {
            return Ok(Vec::new());
        }
        self.call("onEvent", serde_json::json!([event]))
    }

    fn capability_response(
        &mut self,
        request_id: &str,
        response: CapabilityResponse,
    ) -> Result<Vec<MessageKind>, RuntimeError> {
        if !self.active {
            return Err(RuntimeError::NotActive);
        }
        let payload = serde_json::from_slice::<serde_json::Value>(&response.payload)
            .unwrap_or(serde_json::Value::Null);
        let response = if response.granted {
            serde_json::json!({
                "protocolVersion": 1,
                "requestId": request_id,
                "result": payload,
            })
        } else {
            serde_json::json!({
                "protocolVersion": 1,
                "requestId": request_id,
                "error": {
                    "code": "permission-denied",
                    "message": response.error.unwrap_or_else(|| "Permission denied".into()),
                },
            })
        };
        let status = self
            .plugin
            .resume_host(&response.to_string())
            .map_err(|error| RuntimeError::Call(error.to_string()))?;
        self.decode_status(status)
    }

    fn cancel(&mut self, instance_id: &str) -> Result<(), RuntimeError> {
        let result = if self.active
            && self
                .plugin
                .has_function("cancel")
                .map_err(|error| RuntimeError::Call(error.to_string()))?
        {
            self.call("cancel", serde_json::json!([instance_id]))
                .map(|_| ())
        } else {
            Ok(())
        };
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

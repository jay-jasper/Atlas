mod javascript;
mod mcp;
mod wasm;

pub use javascript::JavascriptAdapter;
pub use mcp::McpAdapter;
pub use wasm::WasmAdapter;

use atlas_plugin_protocol::{CapabilityResponse, CommandStart, MessageKind, UiOpen};
use atlas_ui_schema::{UiEvent, UiNode, UiPatch, UiSession};
use serde::Deserialize;

pub const MAX_RUNTIME_OUTPUT_BYTES: usize = 256 * 1024;

pub trait RuntimeAdapter {
    fn start(&mut self, command: CommandStart) -> Result<Vec<MessageKind>, RuntimeError>;
    fn event(&mut self, event: UiEvent) -> Result<Vec<MessageKind>, RuntimeError>;
    fn capability_response(
        &mut self,
        _response: CapabilityResponse,
    ) -> Result<Vec<MessageKind>, RuntimeError> {
        Ok(Vec::new())
    }
    fn cancel(&mut self, instance_id: &str) -> Result<(), RuntimeError>;
    fn health(&mut self) -> RuntimeHealth;
    fn shutdown(&mut self) -> Result<(), RuntimeError>;
}

pub struct RuntimeDriver {
    adapter: Box<dyn RuntimeAdapter>,
}

impl RuntimeDriver {
    pub fn new(adapter: Box<dyn RuntimeAdapter>) -> Self {
        Self { adapter }
    }

    pub fn handle(
        &mut self,
        instance_id: &str,
        message: MessageKind,
    ) -> Result<Vec<MessageKind>, RuntimeError> {
        match message {
            MessageKind::Start(command) => self.adapter.start(command),
            MessageKind::UiEvent(event) => self.adapter.event(event),
            MessageKind::CapabilityResponse(response) => self.adapter.capability_response(response),
            MessageKind::Cancel => {
                self.adapter.cancel(instance_id)?;
                Ok(vec![MessageKind::UiClose])
            }
            MessageKind::Health => {
                let health = self.adapter.health();
                if health.is_ready() {
                    Ok(vec![MessageKind::Health])
                } else {
                    Err(RuntimeError::Call(format!(
                        "runtime is not ready: {health:?}"
                    )))
                }
            }
            MessageKind::Shutdown => {
                self.adapter.shutdown()?;
                Ok(Vec::new())
            }
            _ => Err(RuntimeError::Call(
                "message is not accepted by a runtime adapter".into(),
            )),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RuntimeHealth {
    Ready,
    Busy,
    Failed(String),
    Stopped,
}

impl RuntimeHealth {
    pub fn is_ready(&self) -> bool {
        matches!(self, Self::Ready)
    }
}

#[derive(Debug, thiserror::Error)]
pub enum RuntimeError {
    #[error("runtime failed to load: {0}")]
    Load(String),
    #[error("runtime call failed: {0}")]
    Call(String),
    #[error("runtime output is invalid: {0}")]
    Output(String),
    #[error("runtime has already started")]
    AlreadyStarted,
    #[error("runtime is not active")]
    NotActive,
    #[error("runtime has stopped")]
    Stopped,
    #[error("MCP protocol failed: {0}")]
    Mcp(String),
}

#[derive(Clone, Default)]
pub(crate) struct UiOutputState {
    session: Option<UiSession>,
    next_session_id: u64,
}

impl UiOutputState {
    pub fn decode(&mut self, bytes: &[u8]) -> Result<Vec<MessageKind>, RuntimeError> {
        if bytes.len() > MAX_RUNTIME_OUTPUT_BYTES {
            return Err(RuntimeError::Output(format!(
                "payload exceeds {MAX_RUNTIME_OUTPUT_BYTES} bytes"
            )));
        }
        let emissions: Vec<RuntimeEmission> = serde_json::from_slice(bytes)
            .map_err(|error| RuntimeError::Output(error.to_string()))?;
        let mut candidate = self.clone();
        let messages = candidate.apply_emissions(emissions)?;
        *self = candidate;
        Ok(messages)
    }

    fn apply_emissions(
        &mut self,
        emissions: Vec<RuntimeEmission>,
    ) -> Result<Vec<MessageKind>, RuntimeError> {
        let mut messages = Vec::with_capacity(emissions.len());
        for emission in emissions {
            match emission {
                RuntimeEmission::Open { title, root } => {
                    if self.session.is_some() {
                        return Err(RuntimeError::Output(
                            "runtime opened a second UI session".into(),
                        ));
                    }
                    self.next_session_id = self.next_session_id.saturating_add(1);
                    self.session = Some(
                        UiSession::new(format!("runner-{}", self.next_session_id), root.clone())
                            .map_err(|error| RuntimeError::Output(error.to_string()))?,
                    );
                    messages.push(MessageKind::UiOpen(UiOpen { title, root }));
                }
                RuntimeEmission::Patch { patch } => {
                    let session = self.session.as_mut().ok_or_else(|| {
                        RuntimeError::Output("UI patch arrived before UI open".into())
                    })?;
                    session
                        .apply(patch.clone())
                        .map_err(|error| RuntimeError::Output(error.to_string()))?;
                    messages.push(MessageKind::UiPatch(patch));
                }
                RuntimeEmission::Close => {
                    if self.session.take().is_none() {
                        return Err(RuntimeError::Output(
                            "UI close arrived without an open session".into(),
                        ));
                    }
                    messages.push(MessageKind::UiClose);
                }
            }
        }
        Ok(messages)
    }

    pub fn close(&mut self) {
        self.session = None;
    }
}

#[derive(Deserialize)]
#[serde(tag = "type")]
enum RuntimeEmission {
    #[serde(rename = "ui-open")]
    Open { title: String, root: UiNode },
    #[serde(rename = "ui-patch")]
    Patch { patch: UiPatch },
    #[serde(rename = "ui-close")]
    Close,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn invalid_emission_batch_does_not_mutate_ui_state() {
        let mut state = UiOutputState::default();
        let invalid = br#"[
          {"type":"ui-open","title":"Bad","root":{"kind":"text","id":"root","value":"ready"}},
          {"type":"ui-patch","patch":{"kind":"set-text","id":"missing","value":"bad"}}
        ]"#;
        assert!(state.decode(invalid).is_err());

        let valid = br#"[
          {"type":"ui-open","title":"Good","root":{"kind":"text","id":"root","value":"ready"}},
          {"type":"ui-close"}
        ]"#;
        assert!(state.decode(valid).is_ok());
    }
}

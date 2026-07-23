use atlas_ui_schema::{UiEvent, UiNode, UiPatch};
use serde::{Deserialize, Serialize};

pub const PROTOCOL_VERSION: u16 = 1;
pub const MAX_FRAME_BYTES: usize = 1024 * 1024;
const FRAME_PREFIX_BYTES: usize = size_of::<u32>();

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Envelope {
    pub protocol_version: u16,
    pub plugin_id: String,
    pub command_id: String,
    pub instance_id: String,
    pub request_id: String,
    pub message: MessageKind,
}

impl Envelope {
    pub fn new(
        plugin_id: impl Into<String>,
        command_id: impl Into<String>,
        instance_id: impl Into<String>,
        request_id: impl Into<String>,
        message: MessageKind,
    ) -> Self {
        Self {
            protocol_version: PROTOCOL_VERSION,
            plugin_id: plugin_id.into(),
            command_id: command_id.into(),
            instance_id: instance_id.into(),
            request_id: request_id.into(),
            message,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "payload", rename_all = "kebab-case")]
pub enum MessageKind {
    Hello(Hello),
    HelloAck(HelloAck),
    Start(CommandStart),
    Cancel,
    Shutdown,
    Health,
    UiOpen(UiOpen),
    UiPatch(UiPatch),
    UiClose,
    UiEvent(UiEvent),
    CapabilityRequest(CapabilityRequest),
    CapabilityResponse(CapabilityResponse),
    Log(DiagnosticEvent),
    Metric(ResourceMetric),
    RuntimeError(RuntimeFailure),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Hello {
    pub nonce: [u8; 32],
    pub package_root: [u8; 32],
    pub min_version: u16,
    pub max_version: u16,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HelloAck {
    pub nonce: [u8; 32],
    pub package_root: [u8; 32],
    pub selected_version: u16,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CommandStart {
    pub arguments: Vec<String>,
    pub environment: Vec<(String, String)>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct UiOpen {
    pub title: String,
    pub root: UiNode,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CapabilityRequest {
    pub capability: String,
    pub operation: String,
    pub resource: Option<String>,
    pub payload: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CapabilityResponse {
    pub granted: bool,
    pub payload: Vec<u8>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DiagnosticEvent {
    pub level: DiagnosticLevel,
    pub target: String,
    pub message: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum DiagnosticLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ResourceMetric {
    pub cpu_time_millis: u64,
    pub resident_memory_bytes: u64,
    pub emitted_at_unix_millis: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RuntimeFailure {
    pub code: String,
    pub message: String,
    pub recoverable: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum FrameError {
    #[error("frame is missing its 4-byte length prefix")]
    MissingLengthPrefix,
    #[error("frame body is {0} bytes, exceeding the {MAX_FRAME_BYTES}-byte limit")]
    FrameTooLarge(usize),
    #[error("frame declares {declared} body bytes but contains {actual}")]
    LengthMismatch { declared: usize, actual: usize },
    #[error("protocol version {0} is unsupported")]
    UnsupportedProtocolVersion(u16),
    #[error("failed to encode protocol frame: {0}")]
    Encode(String),
    #[error("failed to decode protocol frame: {0}")]
    Decode(String),
}

pub fn encode_frame(envelope: &Envelope) -> Result<Vec<u8>, FrameError> {
    validate_protocol_version(envelope.protocol_version)?;
    let body =
        serde_cbor::to_vec(envelope).map_err(|error| FrameError::Encode(error.to_string()))?;
    if body.len() > MAX_FRAME_BYTES {
        return Err(FrameError::FrameTooLarge(body.len()));
    }

    let body_len = u32::try_from(body.len()).map_err(|_| FrameError::FrameTooLarge(body.len()))?;
    let mut frame = Vec::with_capacity(FRAME_PREFIX_BYTES + body.len());
    frame.extend_from_slice(&body_len.to_be_bytes());
    frame.extend_from_slice(&body);
    Ok(frame)
}

pub fn decode_frame(frame: &[u8]) -> Result<Envelope, FrameError> {
    if frame.len() < FRAME_PREFIX_BYTES {
        return Err(FrameError::MissingLengthPrefix);
    }

    let declared = u32::from_be_bytes(
        frame[..FRAME_PREFIX_BYTES]
            .try_into()
            .expect("length prefix size was checked"),
    ) as usize;
    if declared > MAX_FRAME_BYTES {
        return Err(FrameError::FrameTooLarge(declared));
    }

    let body = &frame[FRAME_PREFIX_BYTES..];
    if body.len() > MAX_FRAME_BYTES {
        return Err(FrameError::FrameTooLarge(body.len()));
    }
    if body.len() != declared {
        return Err(FrameError::LengthMismatch {
            declared,
            actual: body.len(),
        });
    }

    let envelope: Envelope =
        serde_cbor::from_slice(body).map_err(|error| FrameError::Decode(error.to_string()))?;
    validate_protocol_version(envelope.protocol_version)?;
    Ok(envelope)
}

fn validate_protocol_version(version: u16) -> Result<(), FrameError> {
    if version == 0 {
        Err(FrameError::UnsupportedProtocolVersion(version))
    } else {
        Ok(())
    }
}

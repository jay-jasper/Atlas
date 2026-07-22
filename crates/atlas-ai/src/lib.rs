//! Cross-platform AI center core: provider/session/preset storage,
//! OpenAI-compatible streaming client, and Markdown export.
//! UI-free by design — every frontend (macOS SwiftUI today) talks to this
//! crate through the FFI layer.

pub mod models;
pub mod storage;

pub use models::*;
pub use storage::AiStore;

#[derive(Debug, thiserror::Error)]
pub enum AiError {
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
    #[error("serialization error: {0}")]
    Serde(#[from] serde_json::Error),
    #[error("corrupt data file: {0}")]
    Corrupt(String),
    #[error("not found: {0}")]
    NotFound(String),
}

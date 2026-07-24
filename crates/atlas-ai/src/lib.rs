//! Cross-platform AI center core: provider/session/preset storage,
//! OpenAI-compatible streaming client, and Markdown export.
//! UI-free by design — every frontend (macOS SwiftUI today) talks to this
//! crate through the FFI layer.

pub mod cli;
pub mod client;
pub mod commands;
pub mod export;
pub mod models;
pub mod sse;
pub mod storage;

pub use cli::{detect_clis, run_prompt_via_cli, DetectedCli};
pub use client::{build_body, send_streaming, SendRequest, StreamSink};
pub use commands::{render_prompt, AiCommand, AiCommandOutput, AiCommandStore};
pub use export::export_markdown;
pub use models::*;
pub use sse::{SseEvent, SseParser};
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

//! # atlas-plugin-host
//!
//! Host runtime foundation for the Atlas plugin platform (roadmap Phase 4).
//!
//! This crate implements the runtime-agnostic core of the dual-track plugin
//! system described in `docs/superpowers/specs/2026-05-24-plugin-system-design.md`:
//!
//! - [`manifest`] — parsing and validation of `plugin.toml` for both the WASM
//!   (Track A) and MCP (Track B) runtimes.
//! - [`capabilities`] — capability gating enforced at the host API boundary.
//! - [`registry`] — an in-memory registry of installed plugins.
//!
//! The wasmtime/WIT host (Phase α) and MCP subprocess host (Phase δ) build on
//! top of this manifest + capability layer.

pub mod capabilities;
pub mod dist;
pub mod manifest;
pub mod mcp;
pub mod mcp_transport;
pub mod registry;
pub mod ui;
pub mod wasm_host;

pub use capabilities::{CapabilityError, CapabilityGuard};
pub use manifest::{Capabilities, ManifestError, PluginManifest, Runtime, RuntimeKind};
pub use registry::{PluginRegistry, RegistryError};
pub use ui::{UiError, UiEvent, UiNode};

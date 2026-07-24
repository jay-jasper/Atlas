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

pub mod broker;
pub mod capabilities;
pub mod developer_mode;
pub mod diagnostics;
pub mod dist;
pub mod hub;
pub mod limits;
#[cfg(feature = "lua")]
pub mod lua;
pub mod manifest;
pub mod mcp;
pub mod mcp_transport;
pub mod package_manager;
pub mod registry;
pub mod runner_client;
pub mod runtime;
pub mod storage;
pub mod supervisor;
pub mod ui;
pub mod wasm_host;

pub use broker::{
    BrokerDecision, BrokerError, CapabilityBroker, CapabilityGrant, CapabilityId, CapabilityTarget,
    PluginIdentity,
};
pub use capabilities::{CapabilityError, CapabilityGuard};
pub use developer_mode::{
    ApprovedCommand, DeveloperGrant, DeveloperGrantStore, DeveloperModeController,
    DeveloperModeError, DeveloperRunnerTerminator,
};
pub use diagnostics::{
    DiagnosticCategory, DiagnosticEvent, DiagnosticExport, DiagnosticPayload,
    DiagnosticPayloadKind, DiagnosticPolicy, DiagnosticStore, DiagnosticsError, StableErrorCode,
};
pub use limits::{LimitError, LimitTracker, RuntimeLimits, RESOURCE_POLICY_VERSION};
pub use manifest::{
    Capabilities, ManifestError, PluginManifest, PluginManifestV2, Runtime, RuntimeKind,
};
pub use package_manager::{
    GrantSet, InstallRecord, ManagedPluginStatus, PackageActivator, PackageLifecycle,
    PackageManagerError, PluginPackageManager, StageState, StorageMigration,
};
pub use registry::{PluginRegistry, RegistryError};
pub use runner_client::{RunnerClient, RunnerError};
pub use runtime::{PluginRuntimeEntry, PluginRuntimeError, PluginRuntimeHost};
pub use storage::{
    ExternalFileHandle, PluginStorage, StorageError, StorageSnapshot, StorageTransaction,
};
pub use supervisor::{
    Clock, CommandHandle, CommandInvocation, CommandStatus, ManagedRunner, MonotonicClock,
    PluginSupervisor, ProcessRunnerLauncher, RecoveryReport, RunnerLauncher, SupervisorError,
    Termination,
};
pub use ui::{UiError, UiEvent, UiNode, UiPatch};
pub use wasm_host::{WasmError, WasmHost, WasmLimits};

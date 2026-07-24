//! Atlas FFI Crate
//!
//! This crate provides a Foreign Function Interface (FFI) for the Atlas core functionality,
//! allowing it to be used from other languages via UniFFI.

// UniFFI's UDL scaffolding generates a separated doc comment. Keep strict
// Clippy enabled for handwritten code while tolerating that upstream output.
#![allow(clippy::empty_line_after_doc_comments)]

use atlas_core::AtlasCore;
#[cfg(feature = "executable-plugins")]
use atlas_plugin_host::PackageLifecycle;
use once_cell::sync::Lazy;
#[cfg(feature = "executable-plugins")]
use once_cell::sync::OnceCell;
use std::sync::{Arc, Mutex};
use thiserror::Error;
use tokio::runtime::Runtime;
use tokio::task::JoinHandle;

uniffi::include_scaffolding!("atlas");

/// Global instance of the Atlas core to preserve state across FFI calls.
static CORE: Lazy<Mutex<AtlasCore>> = Lazy::new(|| Mutex::new(AtlasCore::new()));
#[cfg(feature = "executable-plugins")]
static PLUGIN_STORAGE: OnceCell<Arc<atlas_plugin_host::PluginStorage>> = OnceCell::new();
#[cfg(feature = "executable-plugins")]
static PLUGIN_STORAGE_ROOT: OnceCell<std::path::PathBuf> = OnceCell::new();
#[cfg(feature = "executable-plugins")]
static PLUGIN_PLATFORM: Lazy<Mutex<Option<PluginPlatform>>> = Lazy::new(|| Mutex::new(None));

/// Control the monitoring background task.
static MONITOR_HANDLE: Lazy<Mutex<Option<JoinHandle<()>>>> = Lazy::new(|| Mutex::new(None));

/// Global Tokio runtime for background tasks.
static RUNTIME: Lazy<Runtime> =
    Lazy::new(|| Runtime::new().expect("Failed to create Tokio runtime"));
static SEARCH_SERVICE: Lazy<atlas_core::search::SearchService> =
    Lazy::new(atlas_core::search::SearchService::new);

#[derive(Debug, Error)]
pub enum AtlasError {
    #[error("Atlas Core lock is poisoned")]
    LockPoisoned,
    #[error("Monitoring error: {0}")]
    MonitoringError(String),
    #[error("Process error: {0}")]
    ProcessError(String),
    #[error("Capture error: {0}")]
    CaptureError(String),
    #[error("Feature is disabled: {0}")]
    FeatureDisabled(String),
    #[error("Entitlement denied: {0}")]
    EntitlementDenied(String),
    #[error("Plugin error: {0}")]
    PluginError(String),
    #[error("AI error: {0}")]
    AiError(String),
    #[error("Search error: {0}")]
    SearchError(String),
}

/// Represents the state of a feature module for FFI.
pub enum FeatureStatus {
    Enabled,
    Disabled,
}

pub enum CoreEdition {
    Free,
    Pro,
    Community,
}

impl From<CoreEdition> for atlas_core::features::Edition {
    fn from(edition: CoreEdition) -> Self {
        match edition {
            CoreEdition::Free => Self::Free,
            CoreEdition::Pro => Self::Pro,
            CoreEdition::Community => Self::Community,
        }
    }
}

/// A record representing a feature and its current status for FFI.
pub struct FeatureEntry {
    pub name: String,
    pub status: FeatureStatus,
}

pub enum PluginRuntime {
    Wasm,
    Mcp,
    Js,
}

pub struct PluginEntry {
    pub id: String,
    pub name: String,
    pub version: String,
    pub runtime: PluginRuntime,
    pub ui_json: String,
}

pub struct PluginInstallPreview {
    pub name: String,
    pub version: String,
    pub network_hosts: Vec<String>,
    pub storage: bool,
    pub clipboard: bool,
    pub webview: bool,
    pub webview_bridge: bool,
    pub exposed_tools: Vec<String>,
}

pub enum PluginStageState {
    AwaitingConsent,
    Ready,
}

pub struct PluginCapabilityGrant {
    pub capability: String,
    pub target: Option<String>,
}

pub struct PluginStageResult {
    pub stage_id: String,
    pub plugin_id: String,
    pub name: String,
    pub version: String,
    pub publisher: String,
    pub package_root: String,
    pub state: PluginStageState,
    pub requested_capabilities: Vec<String>,
}

pub enum PluginHostEventKind {
    ConsentRequired,
    StatusChanged,
    UiOpen,
    UiPatch,
    UiClose,
    HostRequest,
    Diagnostic,
    Error,
}

pub struct PluginHostEvent {
    pub kind: PluginHostEventKind,
    pub plugin_id: String,
    pub command_id: Option<String>,
    pub instance_id: Option<String>,
    pub session_id: Option<String>,
    pub request_id: Option<String>,
    pub payload_json: String,
}

pub trait PluginPlatformCallback: Send + Sync {
    fn on_plugin_event(&self, event: PluginHostEvent);
}

pub struct PluginStatusRecord {
    pub plugin_id: String,
    pub version: String,
    pub publisher: String,
    pub package_root: String,
    pub trust_tier: String,
    pub granted_capabilities: Vec<String>,
    pub denied_capabilities: Vec<String>,
    pub observing_update: bool,
}

pub struct PluginDiagnosticRecord {
    pub plugin_id: String,
    pub json: String,
    pub event_count: u64,
    pub encoded_bytes: u64,
}

#[cfg(feature = "executable-plugins")]
#[derive(Clone)]
struct PendingPluginStage {
    package: atlas_plugin_package::VerifiedPackage,
    is_update: bool,
}

#[cfg(feature = "executable-plugins")]
struct PendingHostRequest {
    plugin_id: String,
    command_id: String,
    instance_id: String,
    runner_request_id: String,
}

#[cfg(feature = "executable-plugins")]
struct PluginPlatform {
    callback: Arc<dyn PluginPlatformCallback>,
    supervisor: Arc<atlas_plugin_host::PluginSupervisor>,
    manager: atlas_plugin_host::PluginPackageManager,
    broker: atlas_plugin_host::CapabilityBroker,
    diagnostics: atlas_plugin_host::DiagnosticStore,
    developer_mode: Arc<atlas_plugin_host::DeveloperModeController>,
    developer_grants: Arc<atlas_plugin_host::DeveloperGrantStore>,
    package_limits: atlas_plugin_package::PackageLimits,
    trusted_keys: atlas_plugin_package::TrustedKeyStore,
    stages: std::collections::HashMap<String, PendingPluginStage>,
    pending_host_requests: std::collections::HashMap<String, PendingHostRequest>,
}

/// A snapshot of a single CPU core for FFI.
pub struct CpuCoreSnapshot {
    pub name: String,
    pub usage: f32,
    pub frequency_mhz: u64,
}

/// A snapshot of a running process for FFI.
pub struct ProcessSnapshot {
    pub pid: u32,
    pub name: String,
    pub cpu_usage: f32,
    pub mem_bytes: u64,
}

/// A snapshot of a network interface for FFI.
pub struct NetworkInterfaceSnapshot {
    pub name: String,
    pub upload_bps: u64,
    pub download_bps: u64,
}

/// A snapshot of a disk for FFI.
pub struct DiskSnapshot {
    pub name: String,
    pub mount_point: String,
    pub total_bytes: u64,
    pub used_bytes: u64,
    pub available_bytes: u64,
}

/// A snapshot of battery state for FFI.
pub struct BatterySnapshot {
    pub charge_percent: f32,
    pub is_charging: bool,
    pub time_to_empty_secs: Option<i64>,
    pub time_to_full_secs: Option<i64>,
    pub health_percent: f32,
    pub cycle_count: Option<u32>,
}

/// A single temperature reading for FFI.
pub struct TemperatureSnapshot {
    pub label: String,
    pub celsius: f32,
}

/// A snapshot of system performance metrics for FFI.
pub struct SystemSnapshot {
    pub cpu_usage: f32,
    pub mem_used_bytes: u64,
    pub mem_total_bytes: u64,
    pub net_upload_bps: u64,
    pub net_download_bps: u64,
    pub cpu_cores: Vec<CpuCoreSnapshot>,
    pub mem_free_bytes: u64,
    pub mem_available_bytes: u64,
    pub swap_used_bytes: u64,
    pub swap_total_bytes: u64,
    pub top_cpu_processes: Vec<ProcessSnapshot>,
    pub top_mem_processes: Vec<ProcessSnapshot>,
    pub network_interfaces: Vec<NetworkInterfaceSnapshot>,
    pub disks: Vec<DiskSnapshot>,
    pub battery: Option<BatterySnapshot>,
    pub temperatures: Vec<TemperatureSnapshot>,
}

/// Information about a process associated with a network port for FFI.
pub struct PortProcessInfo {
    pub port: u16,
    pub pid: u32,
    pub process_name: String,
}

pub enum SearchIndexPhase {
    Idle,
    Loading,
    Scanning,
    Ready,
    Error,
}

pub struct SearchDocumentInput {
    pub id: String,
    pub namespace: String,
    pub title: String,
    pub subtitle: String,
    pub keywords: Vec<String>,
    pub path: String,
    pub kind: String,
    pub modified_at: u64,
}

pub struct SearchResultEntry {
    pub id: String,
    pub namespace: String,
    pub title: String,
    pub subtitle: String,
    pub path: String,
    pub kind: String,
    pub score: i64,
    pub title_highlight_offsets: Vec<u32>,
}

pub struct SearchIndexStatus {
    pub phase: SearchIndexPhase,
    pub indexed_count: u64,
    pub last_error: Option<String>,
}

/// Callback interface for receiving real-time system monitoring snapshots.
pub trait SystemMonitorCallback: Send + Sync {
    /// Called when a new system snapshot is available.
    fn on_snapshot(&self, snapshot: SystemSnapshot);
}

impl From<atlas_core::features::FeatureStatus> for FeatureStatus {
    fn from(status: atlas_core::features::FeatureStatus) -> Self {
        match status {
            atlas_core::features::FeatureStatus::Enabled => Self::Enabled,
            atlas_core::features::FeatureStatus::Disabled => Self::Disabled,
        }
    }
}

impl From<atlas_core::monitor::models::SystemSnapshot> for SystemSnapshot {
    fn from(s: atlas_core::monitor::models::SystemSnapshot) -> Self {
        SystemSnapshot {
            cpu_usage: s.cpu_usage,
            mem_used_bytes: s.mem_used_bytes,
            mem_total_bytes: s.mem_total_bytes,
            net_upload_bps: s.net_upload_bps,
            net_download_bps: s.net_download_bps,
            cpu_cores: s
                .cpu_cores
                .into_iter()
                .map(|c| CpuCoreSnapshot {
                    name: c.name,
                    usage: c.usage,
                    frequency_mhz: c.frequency_mhz,
                })
                .collect(),
            mem_free_bytes: s.mem_free_bytes,
            mem_available_bytes: s.mem_available_bytes,
            swap_used_bytes: s.swap_used_bytes,
            swap_total_bytes: s.swap_total_bytes,
            top_cpu_processes: s
                .top_cpu_processes
                .into_iter()
                .map(|p| ProcessSnapshot {
                    pid: p.pid,
                    name: p.name,
                    cpu_usage: p.cpu_usage,
                    mem_bytes: p.mem_bytes,
                })
                .collect(),
            top_mem_processes: s
                .top_mem_processes
                .into_iter()
                .map(|p| ProcessSnapshot {
                    pid: p.pid,
                    name: p.name,
                    cpu_usage: p.cpu_usage,
                    mem_bytes: p.mem_bytes,
                })
                .collect(),
            network_interfaces: s
                .network_interfaces
                .into_iter()
                .map(|n| NetworkInterfaceSnapshot {
                    name: n.name,
                    upload_bps: n.upload_bps,
                    download_bps: n.download_bps,
                })
                .collect(),
            disks: s
                .disks
                .into_iter()
                .map(|d| DiskSnapshot {
                    name: d.name,
                    mount_point: d.mount_point,
                    total_bytes: d.total_bytes,
                    used_bytes: d.used_bytes,
                    available_bytes: d.available_bytes,
                })
                .collect(),
            battery: s.battery.map(|b| BatterySnapshot {
                charge_percent: b.charge_percent,
                is_charging: b.is_charging,
                time_to_empty_secs: b.time_to_empty_secs,
                time_to_full_secs: b.time_to_full_secs,
                health_percent: b.health_percent,
                cycle_count: b.cycle_count,
            }),
            temperatures: s
                .temperatures
                .into_iter()
                .map(|t| TemperatureSnapshot {
                    label: t.label,
                    celsius: t.celsius,
                })
                .collect(),
        }
    }
}

/// Returns the current status of the Atlas core.
///
/// This function uses the global `AtlasCore` instance.
pub fn get_core_status() -> Result<String, AtlasError> {
    let core = CORE.lock().map_err(|_| AtlasError::LockPoisoned)?;
    Ok(core.get_status())
}

/// Toggles a feature state.
///
/// Returns true if the feature existed and was toggled.
pub fn toggle_feature(name: String, enabled: bool) -> Result<bool, AtlasError> {
    let mut core = CORE.lock().map_err(|_| AtlasError::LockPoisoned)?;
    core.feature_manager_mut()
        .toggle_feature(&name, enabled)
        .map_err(|error| AtlasError::EntitlementDenied(error.to_string()))
}

pub fn configure_entitlement(edition: CoreEdition) -> Result<(), AtlasError> {
    CORE.lock()
        .map_err(|_| AtlasError::LockPoisoned)?
        .set_edition(edition.into());
    Ok(())
}

fn require_feature(name: &str) -> Result<(), AtlasError> {
    let core = CORE.lock().map_err(|_| AtlasError::LockPoisoned)?;
    if core.feature_manager().is_enabled(name) {
        Ok(())
    } else {
        Err(AtlasError::FeatureDisabled(name.to_string()))
    }
}

/// Returns a list of all available features and their status.
pub fn list_features() -> Result<Vec<FeatureEntry>, AtlasError> {
    // Important Issue 3: release the lock before allocation by binding raw first.
    let raw = CORE
        .lock()
        .map_err(|_| AtlasError::LockPoisoned)?
        .feature_manager()
        .list_features();
    Ok(raw
        .into_iter()
        .map(|(name, status)| FeatureEntry {
            name,
            status: status.into(),
        })
        .collect())
}

pub fn install_wasm_plugin(
    manifest_toml: String,
    wasm_bytes: Vec<u8>,
    ui_json: String,
) -> Result<PluginEntry, AtlasError> {
    let _ = (manifest_toml, wasm_bytes, ui_json);
    Err(legacy_plugin_api_unavailable())
}

pub fn inspect_plugin_manifest(manifest_toml: String) -> Result<PluginInstallPreview, AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = manifest_toml;
        Err(AtlasError::PluginError(
            "Executable plugins are unavailable in this distribution".to_string(),
        ))
    }
    #[cfg(feature = "executable-plugins")]
    {
        let manifest = atlas_plugin_host::PluginManifest::parse(&manifest_toml)
            .map_err(|error| AtlasError::PluginError(error.to_string()))?;
        let capabilities = manifest.capabilities;
        Ok(PluginInstallPreview {
            name: manifest.name,
            version: manifest.version,
            network_hosts: capabilities.network,
            storage: capabilities.storage,
            clipboard: capabilities.clipboard,
            webview: capabilities.webview,
            webview_bridge: capabilities.webview_bridge,
            exposed_tools: capabilities.exposed_tools,
        })
    }
}

pub fn install_mcp_plugin(
    manifest_toml: String,
    ui_json: String,
) -> Result<PluginEntry, AtlasError> {
    let _ = (manifest_toml, ui_json);
    Err(legacy_plugin_api_unavailable())
}

pub fn install_js_plugin(
    manifest_toml: String,
    source: String,
    ui_json: String,
) -> Result<PluginEntry, AtlasError> {
    let _ = (manifest_toml, source, ui_json);
    Err(legacy_plugin_api_unavailable())
}

pub fn list_plugins() -> Result<Vec<PluginEntry>, AtlasError> {
    Ok(Vec::new())
}

pub fn uninstall_plugin(id: String) -> Result<bool, AtlasError> {
    let _ = id;
    Ok(false)
}

pub fn dispatch_plugin_event(id: String, event_json: String) -> Result<String, AtlasError> {
    let _ = (id, event_json);
    Err(legacy_plugin_api_unavailable())
}

fn legacy_plugin_api_unavailable() -> AtlasError {
    AtlasError::PluginError(
        "Legacy in-process plugin execution is disabled; migrate or build an .atlasplugin package"
            .into(),
    )
}

pub fn initialize_plugin_storage(
    root_path: String,
    mut content_key: Vec<u8>,
) -> Result<(), AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    let result = {
        let _ = root_path;
        Err(AtlasError::PluginError(
            "Executable plugins are unavailable in this distribution".to_string(),
        ))
    };
    #[cfg(feature = "executable-plugins")]
    let result = {
        let root_path = std::path::PathBuf::from(root_path);
        atlas_plugin_host::PluginStorage::from_key_bytes(&root_path, &content_key)
            .map(Arc::new)
            .map_err(|error| AtlasError::PluginError(error.to_string()))
            .and_then(|storage| {
                if PLUGIN_STORAGE.get().is_some() || PLUGIN_STORAGE_ROOT.get().is_some() {
                    return Err(AtlasError::PluginError(
                        "Plugin storage has already been initialized for this process".to_string(),
                    ));
                }
                PLUGIN_STORAGE_ROOT.set(root_path).map_err(|_| {
                    AtlasError::PluginError(
                        "Plugin storage root has already been initialized".to_string(),
                    )
                })?;
                PLUGIN_STORAGE.set(storage).map_err(|_| {
                    AtlasError::PluginError(
                        "Plugin storage has already been initialized for this process".to_string(),
                    )
                })
            })
    };
    content_key.fill(0);
    result
}

pub fn plugin_platform_start(callback: Box<dyn PluginPlatformCallback>) -> Result<(), AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = callback;
        return Err(executable_plugins_unavailable());
    }
    #[cfg(feature = "executable-plugins")]
    {
        let storage = PLUGIN_STORAGE.get().cloned().ok_or_else(|| {
            AtlasError::PluginError(
                "Plugin storage must be initialized from Keychain before platform start".into(),
            )
        })?;
        let storage_root = PLUGIN_STORAGE_ROOT.get().cloned().ok_or_else(|| {
            AtlasError::PluginError("Plugin storage root is not initialized".into())
        })?;
        let mut platform = PLUGIN_PLATFORM
            .lock()
            .map_err(|_| AtlasError::LockPoisoned)?;
        if platform.is_some() {
            return Err(AtlasError::PluginError(
                "Plugin platform has already been started".into(),
            ));
        }
        let clock: Arc<dyn atlas_plugin_host::Clock> =
            Arc::new(atlas_plugin_host::MonotonicClock::default());
        let supervisor = Arc::new(atlas_plugin_host::PluginSupervisor::new(
            Arc::new(atlas_plugin_host::ProcessRunnerLauncher::new(
                embedded_plugin_runner_path()?,
            )),
            Arc::clone(&clock),
        ));
        let activator: Arc<dyn atlas_plugin_host::PackageActivator> = supervisor.clone();
        let mut manager_keys = atlas_plugin_package::TrustedKeyStore::new();
        manager_keys.set_developer_mode(true);
        let manager = atlas_plugin_host::PluginPackageManager::new_with_verification(
            storage_root.join("managed-platform"),
            Arc::clone(&storage),
            activator,
            Arc::new(atlas_plugin_host::package_manager::MetadataStorageMigration),
            Arc::clone(&clock),
            atlas_plugin_package::PackageLimits::default(),
            manager_keys,
        )
        .map_err(plugin_error)?;
        let mut broker = atlas_plugin_host::CapabilityBroker::new();
        for (package, grants) in manager.restore_active(false).map_err(plugin_error)? {
            let grants = grants
                .iter()
                .map(|grant| atlas_plugin_host::CapabilityGrant::parse(grant))
                .collect::<Result<Vec<_>, _>>()
                .map_err(plugin_error)?;
            broker
                .register_manifest(package.manifest(), grants)
                .map_err(plugin_error)?;
        }
        let developer_grants = Arc::new(atlas_plugin_host::DeveloperGrantStore::new(Arc::clone(
            &storage,
        )));
        let terminator: Arc<dyn atlas_plugin_host::DeveloperRunnerTerminator> = supervisor.clone();
        let developer_mode = Arc::new(atlas_plugin_host::DeveloperModeController::new(
            Arc::clone(&developer_grants),
            terminator,
        ));
        *platform = Some(PluginPlatform {
            callback: Arc::from(callback),
            supervisor,
            manager,
            broker,
            diagnostics: atlas_plugin_host::DiagnosticStore::new(
                atlas_plugin_host::DiagnosticPolicy::default(),
                clock,
            ),
            developer_mode,
            developer_grants,
            package_limits: atlas_plugin_package::PackageLimits::default(),
            trusted_keys: atlas_plugin_package::TrustedKeyStore::new(),
            stages: std::collections::HashMap::new(),
            pending_host_requests: std::collections::HashMap::new(),
        });
        Ok(())
    }
}

pub fn plugin_stage_package(package_bytes: Vec<u8>) -> Result<PluginStageResult, AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = package_bytes;
        return Err(executable_plugins_unavailable());
    }
    #[cfg(feature = "executable-plugins")]
    {
        let (result, callback, event) = {
            let mut guard = PLUGIN_PLATFORM
                .lock()
                .map_err(|_| AtlasError::LockPoisoned)?;
            let platform = guard
                .as_mut()
                .ok_or_else(|| AtlasError::PluginError("Plugin platform is not started".into()))?;
            let package = atlas_plugin_package::verify_archive(
                std::io::Cursor::new(package_bytes),
                &platform.package_limits,
                &platform.trusted_keys,
            )
            .map_err(plugin_error)?;
            let manifest = package.manifest().clone();
            let is_update = platform.manager.active_root(&manifest.id).is_ok();
            let state = if is_update {
                match platform
                    .manager
                    .stage_update(package.clone())
                    .map_err(plugin_error)?
                {
                    atlas_plugin_host::StageState::Ready => PluginStageState::Ready,
                    atlas_plugin_host::StageState::AwaitingConsent => {
                        PluginStageState::AwaitingConsent
                    }
                }
            } else {
                PluginStageState::AwaitingConsent
            };
            let stage_id = secure_identifier("stage")?;
            let result = PluginStageResult {
                stage_id: stage_id.clone(),
                plugin_id: manifest.id.clone(),
                name: manifest.name.clone(),
                version: manifest.version.clone(),
                publisher: manifest.publisher.clone(),
                package_root: package.root().to_hex(),
                state,
                requested_capabilities: manifest.capabilities.clone(),
            };
            platform
                .stages
                .insert(stage_id, PendingPluginStage { package, is_update });
            let payload_json = serde_json::json!({
                "stageId": result.stage_id,
                "pluginId": result.plugin_id,
                "name": result.name,
                "version": result.version,
                "publisher": result.publisher,
                "packageRoot": result.package_root,
                "state": match result.state {
                    PluginStageState::AwaitingConsent => "awaiting-consent",
                    PluginStageState::Ready => "ready",
                },
                "requestedCapabilities": result.requested_capabilities,
            })
            .to_string();
            let event = PluginHostEvent {
                kind: PluginHostEventKind::ConsentRequired,
                plugin_id: result.plugin_id.clone(),
                command_id: None,
                instance_id: None,
                session_id: None,
                request_id: Some(result.stage_id.clone()),
                payload_json,
            };
            (result, Arc::clone(&platform.callback), event)
        };
        callback.on_plugin_event(event);
        Ok(result)
    }
}

pub fn plugin_apply_grants(
    stage_id: String,
    grants: Vec<PluginCapabilityGrant>,
) -> Result<(), AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = (stage_id, grants);
        return Err(executable_plugins_unavailable());
    }
    #[cfg(feature = "executable-plugins")]
    {
        let (callback, event) = {
            let mut guard = PLUGIN_PLATFORM
                .lock()
                .map_err(|_| AtlasError::LockPoisoned)?;
            let platform = guard
                .as_mut()
                .ok_or_else(|| AtlasError::PluginError("Plugin platform is not started".into()))?;
            let pending = platform
                .stages
                .get(&stage_id)
                .cloned()
                .ok_or_else(|| AtlasError::PluginError("Unknown plugin stage".into()))?;
            let grant_strings = grants
                .iter()
                .map(plugin_grant_string)
                .collect::<Result<atlas_plugin_host::GrantSet, _>>()?;
            if pending.is_update {
                platform
                    .manager
                    .approve_staged(pending.package.plugin_id(), grant_strings.clone())
                    .map_err(plugin_error)?;
                platform
                    .manager
                    .activate_staged(pending.package.plugin_id())
                    .map_err(plugin_error)?;
            } else {
                platform
                    .manager
                    .install(pending.package.clone(), grant_strings.clone())
                    .map_err(plugin_error)?;
            }
            let broker_grants = grant_strings
                .iter()
                .map(|grant| atlas_plugin_host::CapabilityGrant::parse(grant))
                .collect::<Result<Vec<_>, _>>()
                .map_err(plugin_error)?;
            platform
                .broker
                .register_manifest(pending.package.manifest(), broker_grants)
                .map_err(plugin_error)?;
            if pending.package.trust_tier() == atlas_plugin_package::TrustTier::DeveloperMode
                && pending.package.manifest().runtime == atlas_plugin_package::RuntimeKind::Mcp
            {
                platform
                    .developer_mode
                    .register_unsigned_mcp(pending.package.plugin_id())
                    .map_err(plugin_error)?;
            }
            platform.stages.remove(&stage_id);
            let event = PluginHostEvent {
                kind: PluginHostEventKind::StatusChanged,
                plugin_id: pending.package.plugin_id().into(),
                command_id: None,
                instance_id: None,
                session_id: None,
                request_id: Some(stage_id),
                payload_json: serde_json::json!({
                    "version": pending.package.manifest().version,
                    "packageRoot": pending.package.root().to_hex(),
                    "state": "active",
                })
                .to_string(),
            };
            (Arc::clone(&platform.callback), event)
        };
        callback.on_plugin_event(event);
        Ok(())
    }
}

pub fn plugin_platform_statuses() -> Result<Vec<PluginStatusRecord>, AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        return Ok(Vec::new());
    }
    #[cfg(feature = "executable-plugins")]
    {
        with_plugin_platform(|platform| {
            platform
                .manager
                .list_statuses()
                .map_err(plugin_error)
                .map(|statuses| {
                    statuses
                        .into_iter()
                        .map(|status| PluginStatusRecord {
                            plugin_id: status.plugin_id,
                            version: status.version,
                            publisher: status.publisher,
                            package_root: status.package_root.to_hex(),
                            trust_tier: status.trust_tier,
                            granted_capabilities: status.granted_capabilities,
                            denied_capabilities: status.denied_capabilities,
                            observing_update: status.observing_update,
                        })
                        .collect()
                })
        })
    }
}

pub fn plugin_export_diagnostics(plugin_id: String) -> Result<PluginDiagnosticRecord, AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = plugin_id;
        return Err(executable_plugins_unavailable());
    }
    #[cfg(feature = "executable-plugins")]
    {
        with_plugin_platform(|platform| {
            let export = platform
                .diagnostics
                .export(&plugin_id)
                .map_err(plugin_error)?;
            Ok(PluginDiagnosticRecord {
                plugin_id,
                json: export.json,
                event_count: export.event_count as u64,
                encoded_bytes: export.encoded_bytes as u64,
            })
        })
    }
}

pub fn plugin_start_command(
    plugin_id: String,
    command_id: String,
    arguments_json: String,
) -> Result<String, AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = (plugin_id, command_id, arguments_json);
        return Err(executable_plugins_unavailable());
    }
    #[cfg(feature = "executable-plugins")]
    {
        let arguments: Vec<String> = serde_json::from_str(&arguments_json).map_err(plugin_error)?;
        validate_plugin_arguments(&arguments)?;
        let instance_id = secure_identifier("instance")?;
        let (callback, events) = {
            let mut guard = PLUGIN_PLATFORM
                .lock()
                .map_err(|_| AtlasError::LockPoisoned)?;
            let platform = guard
                .as_mut()
                .ok_or_else(|| AtlasError::PluginError("Plugin platform is not started".into()))?;
            let (_, messages) = platform
                .supervisor
                .start_command_and_collect(atlas_plugin_host::CommandInvocation {
                    plugin_id: plugin_id.clone(),
                    command_id: command_id.clone(),
                    instance_id: instance_id.clone(),
                    start: atlas_plugin_protocol::CommandStart {
                        arguments,
                        environment: Vec::new(),
                    },
                    restartable: true,
                    background: false,
                })
                .map_err(plugin_error)?;
            let events = protocol_messages_to_events(
                platform,
                &plugin_id,
                &command_id,
                &instance_id,
                messages,
            )?;
            (Arc::clone(&platform.callback), events)
        };
        for event in events {
            callback.on_plugin_event(event);
        }
        Ok(instance_id)
    }
}

pub fn plugin_send_ui_event(
    plugin_id: String,
    instance_id: String,
    event_json: String,
) -> Result<(), AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = (plugin_id, instance_id, event_json);
        return Err(executable_plugins_unavailable());
    }
    #[cfg(feature = "executable-plugins")]
    {
        let event: atlas_ui_schema::UiEvent =
            serde_json::from_str(&event_json).map_err(plugin_error)?;
        let (callback, events) = {
            let mut guard = PLUGIN_PLATFORM
                .lock()
                .map_err(|_| AtlasError::LockPoisoned)?;
            let platform = guard
                .as_mut()
                .ok_or_else(|| AtlasError::PluginError("Plugin platform is not started".into()))?;
            let messages = platform
                .supervisor
                .send_ui_event(&plugin_id, &instance_id, event)
                .map_err(plugin_error)?;
            let events =
                protocol_messages_to_events(platform, &plugin_id, "", &instance_id, messages)?;
            (Arc::clone(&platform.callback), events)
        };
        for event in events {
            callback.on_plugin_event(event);
        }
        Ok(())
    }
}

pub fn plugin_cancel_command(plugin_id: String, instance_id: String) -> Result<(), AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = (plugin_id, instance_id);
        return Err(executable_plugins_unavailable());
    }
    #[cfg(feature = "executable-plugins")]
    {
        let (callback, events) = {
            let mut guard = PLUGIN_PLATFORM
                .lock()
                .map_err(|_| AtlasError::LockPoisoned)?;
            let platform = guard
                .as_mut()
                .ok_or_else(|| AtlasError::PluginError("Plugin platform is not started".into()))?;
            let messages = platform
                .supervisor
                .cancel_and_collect(&plugin_id, &instance_id)
                .map_err(plugin_error)?;
            let events =
                protocol_messages_to_events(platform, &plugin_id, "", &instance_id, messages)?;
            (Arc::clone(&platform.callback), events)
        };
        for event in events {
            callback.on_plugin_event(event);
        }
        Ok(())
    }
}

pub fn plugin_respond_to_host_request(
    request_id: String,
    response_json: String,
) -> Result<(), AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = (request_id, response_json);
        return Err(executable_plugins_unavailable());
    }
    #[cfg(feature = "executable-plugins")]
    {
        let value: serde_json::Value =
            serde_json::from_str(&response_json).map_err(plugin_error)?;
        let response = atlas_plugin_protocol::CapabilityResponse {
            granted: value
                .get("granted")
                .and_then(serde_json::Value::as_bool)
                .unwrap_or(true),
            payload: serde_json::to_vec(value.get("payload").unwrap_or(&value))
                .map_err(plugin_error)?,
            error: value
                .get("error")
                .and_then(serde_json::Value::as_str)
                .map(str::to_owned),
        };
        let (callback, events) = with_plugin_platform(|platform| {
            let pending = platform
                .pending_host_requests
                .remove(&request_id)
                .ok_or_else(|| AtlasError::PluginError("Unknown host request".into()))?;
            let messages = platform
                .supervisor
                .respond_to_capability(
                    &pending.plugin_id,
                    &pending.instance_id,
                    &pending.runner_request_id,
                    response,
                )
                .map_err(plugin_error)?;
            let events = protocol_messages_to_events(
                platform,
                &pending.plugin_id,
                &pending.command_id,
                &pending.instance_id,
                messages,
            )?;
            Ok((Arc::clone(&platform.callback), events))
        })?;
        for event in events {
            callback.on_plugin_event(event);
        }
        Ok(())
    }
}

pub fn plugin_stop(plugin_id: String) -> Result<(), AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = plugin_id;
        return Err(executable_plugins_unavailable());
    }
    #[cfg(feature = "executable-plugins")]
    {
        with_plugin_platform(|platform| {
            platform
                .supervisor
                .stop_plugin(&plugin_id)
                .map_err(plugin_error)
        })
    }
}

pub fn plugin_restart(plugin_id: String) -> Result<(), AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = plugin_id;
        return Err(executable_plugins_unavailable());
    }
    #[cfg(feature = "executable-plugins")]
    {
        with_plugin_platform(|platform| {
            platform
                .manager
                .restart_active(&plugin_id)
                .map_err(plugin_error)
        })
    }
}

pub fn plugin_reset_command_breaker(
    plugin_id: String,
    command_id: String,
) -> Result<(), AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = (plugin_id, command_id);
        return Err(executable_plugins_unavailable());
    }
    #[cfg(feature = "executable-plugins")]
    {
        with_plugin_platform(|platform| {
            platform
                .supervisor
                .reset_command_breaker(&plugin_id, &command_id);
            Ok(())
        })
    }
}

pub fn plugin_replace_grants(
    plugin_id: String,
    grants: Vec<PluginCapabilityGrant>,
) -> Result<(), AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = (plugin_id, grants);
        return Err(executable_plugins_unavailable());
    }
    #[cfg(feature = "executable-plugins")]
    {
        with_plugin_platform(|platform| {
            let grants = grants
                .iter()
                .map(plugin_grant_string)
                .collect::<Result<atlas_plugin_host::GrantSet, _>>()?;
            let package = platform
                .manager
                .replace_grants(&plugin_id, grants.clone())
                .map_err(plugin_error)?;
            let broker_grants = grants
                .iter()
                .map(|grant| atlas_plugin_host::CapabilityGrant::parse(grant))
                .collect::<Result<Vec<_>, _>>()
                .map_err(plugin_error)?;
            platform
                .broker
                .register_manifest(package.manifest(), broker_grants)
                .map_err(plugin_error)
        })
    }
}

pub fn plugin_rollback(plugin_id: String, clear_incompatible_data: bool) -> Result<(), AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = (plugin_id, clear_incompatible_data);
        return Err(executable_plugins_unavailable());
    }
    #[cfg(feature = "executable-plugins")]
    {
        with_plugin_platform(|platform| {
            if clear_incompatible_data {
                platform
                    .manager
                    .rollback_with_data_clear(&plugin_id)
                    .map(|_| ())
                    .map_err(plugin_error)
            } else {
                atlas_plugin_host::PackageLifecycle::rollback(&platform.manager, &plugin_id)
                    .map(|_| ())
                    .map_err(plugin_error)
            }
        })
    }
}

pub fn plugin_clear_data(plugin_id: String) -> Result<(), AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = plugin_id;
        return Err(executable_plugins_unavailable());
    }
    #[cfg(feature = "executable-plugins")]
    {
        with_plugin_platform(|platform| {
            platform
                .manager
                .clear_data(&plugin_id)
                .map_err(plugin_error)
        })
    }
}

pub fn plugin_platform_uninstall(plugin_id: String) -> Result<(), AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = plugin_id;
        return Err(executable_plugins_unavailable());
    }
    #[cfg(feature = "executable-plugins")]
    {
        with_plugin_platform(|platform| {
            let identity = platform
                .manager
                .list_statuses()
                .map_err(plugin_error)?
                .into_iter()
                .find(|status| status.plugin_id == plugin_id)
                .map(|status| {
                    atlas_plugin_host::PluginIdentity::new(&status.plugin_id, status.publisher)
                });
            atlas_plugin_host::PackageLifecycle::uninstall(&platform.manager, &plugin_id)
                .map_err(plugin_error)?;
            if let Some(identity) = identity {
                platform.broker.remove_plugin(&identity);
            }
            Ok(())
        })
    }
}

pub fn plugin_report_observation_failure(plugin_id: String) -> Result<bool, AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = plugin_id;
        return Ok(false);
    }
    #[cfg(feature = "executable-plugins")]
    {
        with_plugin_platform(|platform| {
            platform
                .manager
                .report_observation_failure(&plugin_id)
                .map_err(plugin_error)
        })
    }
}

pub fn plugin_developer_mode_enabled() -> Result<bool, AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        return Ok(false);
    }
    #[cfg(feature = "executable-plugins")]
    {
        with_plugin_platform(|platform| Ok(platform.developer_mode.is_enabled()))
    }
}

pub fn plugin_set_developer_mode(enabled: bool) -> Result<(), AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = enabled;
        return Err(executable_plugins_unavailable());
    }
    #[cfg(feature = "executable-plugins")]
    {
        with_plugin_platform(|platform| {
            platform.trusted_keys.set_developer_mode(enabled);
            platform
                .manager
                .set_developer_mode(enabled)
                .map_err(plugin_error)?;
            if enabled {
                platform.developer_mode.enable();
                for (package, grants) in platform
                    .manager
                    .restore_developer_active()
                    .map_err(plugin_error)?
                {
                    let broker_grants = grants
                        .iter()
                        .map(|grant| atlas_plugin_host::CapabilityGrant::parse(grant))
                        .collect::<Result<Vec<_>, _>>()
                        .map_err(plugin_error)?;
                    platform
                        .broker
                        .register_manifest(package.manifest(), broker_grants)
                        .map_err(plugin_error)?;
                    if package.manifest().runtime == atlas_plugin_package::RuntimeKind::Mcp {
                        platform
                            .developer_mode
                            .register_unsigned_mcp(package.plugin_id())
                            .map_err(plugin_error)?;
                    }
                }
            } else {
                platform.developer_mode.disable().map_err(plugin_error)?;
                for status in platform
                    .manager
                    .list_statuses()
                    .map_err(plugin_error)?
                    .into_iter()
                    .filter(|status| status.trust_tier == "developer-mode")
                {
                    let _ = platform.supervisor.stop_plugin(&status.plugin_id);
                    platform
                        .broker
                        .remove_plugin(&atlas_plugin_host::PluginIdentity::new(
                            &status.plugin_id,
                            status.publisher,
                        ));
                }
            }
            Ok(())
        })
    }
}

pub fn plugin_save_developer_grant(
    plugin_id: String,
    selected_paths: Vec<String>,
    allow_direct_network: bool,
    approved_commands_json: String,
) -> Result<(), AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = (
            plugin_id,
            selected_paths,
            allow_direct_network,
            approved_commands_json,
        );
        return Err(executable_plugins_unavailable());
    }
    #[cfg(feature = "executable-plugins")]
    {
        let approved_commands: Vec<atlas_plugin_host::ApprovedCommand> =
            serde_json::from_str(&approved_commands_json).map_err(plugin_error)?;
        with_plugin_platform(|platform| {
            platform
                .developer_grants
                .save(atlas_plugin_host::DeveloperGrant {
                    plugin_id,
                    selected_paths: selected_paths.into_iter().map(Into::into).collect(),
                    allow_direct_network,
                    approved_commands,
                })
                .map_err(plugin_error)
        })
    }
}

pub fn plugin_revoke_developer_grant(plugin_id: String) -> Result<bool, AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = plugin_id;
        return Ok(false);
    }
    #[cfg(feature = "executable-plugins")]
    {
        with_plugin_platform(|platform| {
            platform
                .developer_grants
                .revoke(&plugin_id)
                .map_err(plugin_error)
        })
    }
}

pub fn plugin_source_inspect(source_path: String) -> Result<String, AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = source_path;
        return Err(executable_plugins_unavailable());
    }
    #[cfg(feature = "executable-plugins")]
    {
        let report = atlas_plugin_builder::Builder::default()
            .inspect(std::path::Path::new(&source_path))
            .map_err(plugin_error)?;
        serde_json::to_string_pretty(&report).map_err(plugin_error)
    }
}

pub fn plugin_source_build(source_path: String, output_path: String) -> Result<String, AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = (source_path, output_path);
        return Err(executable_plugins_unavailable());
    }
    #[cfg(feature = "executable-plugins")]
    {
        let artifact = atlas_plugin_builder::Builder::default()
            .build(std::path::Path::new(&source_path))
            .map_err(plugin_error)?;
        std::fs::write(&output_path, artifact.bytes()).map_err(plugin_error)?;
        Ok(output_path)
    }
}

#[cfg(not(feature = "executable-plugins"))]
fn executable_plugins_unavailable() -> AtlasError {
    AtlasError::PluginError("Executable plugins are unavailable in this distribution".into())
}

#[cfg(feature = "executable-plugins")]
fn plugin_error(error: impl std::fmt::Display) -> AtlasError {
    AtlasError::PluginError(error.to_string())
}

#[cfg(feature = "executable-plugins")]
fn with_plugin_platform<T>(
    operation: impl FnOnce(&mut PluginPlatform) -> Result<T, AtlasError>,
) -> Result<T, AtlasError> {
    let mut guard = PLUGIN_PLATFORM
        .lock()
        .map_err(|_| AtlasError::LockPoisoned)?;
    let platform = guard
        .as_mut()
        .ok_or_else(|| AtlasError::PluginError("Plugin platform is not started".into()))?;
    operation(platform)
}

#[cfg(feature = "executable-plugins")]
fn embedded_plugin_runner_path() -> Result<std::path::PathBuf, AtlasError> {
    let executable = std::env::current_exe().map_err(plugin_error)?;
    let executable_directory = executable.parent().ok_or_else(|| {
        AtlasError::PluginError("Atlas executable has no parent directory".into())
    })?;
    let candidates = [
        executable_directory.join("atlas-plugin-runner"),
        executable_directory
            .join("../Helpers")
            .join("atlas-plugin-runner"),
    ];
    Ok(candidates
        .iter()
        .find(|candidate| candidate.is_file())
        .cloned()
        .unwrap_or_else(|| candidates[0].clone()))
}

#[cfg(feature = "executable-plugins")]
fn secure_identifier(prefix: &str) -> Result<String, AtlasError> {
    let mut random = [0_u8; 16];
    getrandom::fill(&mut random).map_err(plugin_error)?;
    Ok(format!(
        "{prefix}-{}",
        random
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>()
    ))
}

#[cfg(feature = "executable-plugins")]
fn plugin_grant_string(grant: &PluginCapabilityGrant) -> Result<String, AtlasError> {
    let capability = grant.capability.trim();
    if capability.is_empty() || capability.len() > 128 || capability.contains(':') {
        return Err(AtlasError::PluginError(
            "Plugin capability grant is invalid".into(),
        ));
    }
    match grant.target.as_deref().map(str::trim) {
        Some(target) if !target.is_empty() && target.len() <= 2048 && !target.contains('\0') => {
            Ok(format!("{capability}:{target}"))
        }
        Some(_) => Err(AtlasError::PluginError(
            "Plugin capability target is invalid".into(),
        )),
        None => Ok(capability.to_owned()),
    }
}

#[cfg(feature = "executable-plugins")]
fn validate_plugin_arguments(arguments: &[String]) -> Result<(), AtlasError> {
    if arguments.len() > 128 || arguments.iter().any(|argument| argument.len() > 4096) {
        return Err(AtlasError::PluginError(
            "Plugin command arguments exceed their bounds".into(),
        ));
    }
    Ok(())
}

#[cfg(feature = "executable-plugins")]
fn protocol_messages_to_events(
    platform: &mut PluginPlatform,
    plugin_id: &str,
    command_id: &str,
    instance_id: &str,
    messages: Vec<atlas_plugin_protocol::MessageKind>,
) -> Result<Vec<PluginHostEvent>, AtlasError> {
    let mut events = Vec::new();
    for message in messages {
        match message {
            atlas_plugin_protocol::MessageKind::UiOpen(open) => {
                events.push(plugin_runtime_event(
                    PluginHostEventKind::UiOpen,
                    plugin_id,
                    command_id,
                    instance_id,
                    Some(instance_id.into()),
                    None,
                    serde_json::to_string(&serde_json::json!({
                        "title": open.title,
                        "root": open.root,
                    }))
                    .map_err(plugin_error)?,
                ));
            }
            atlas_plugin_protocol::MessageKind::UiPatch(patch) => {
                events.push(plugin_runtime_event(
                    PluginHostEventKind::UiPatch,
                    plugin_id,
                    command_id,
                    instance_id,
                    Some(instance_id.into()),
                    None,
                    serde_json::to_string(&patch).map_err(plugin_error)?,
                ));
            }
            atlas_plugin_protocol::MessageKind::UiClose => {
                events.push(plugin_runtime_event(
                    PluginHostEventKind::UiClose,
                    plugin_id,
                    command_id,
                    instance_id,
                    Some(instance_id.into()),
                    None,
                    "{}".into(),
                ));
            }
            atlas_plugin_protocol::MessageKind::CapabilityRequest(request) => {
                let denial_code = if is_intrinsic_host_capability(&request.capability) {
                    None
                } else {
                    let status = platform
                        .manager
                        .list_statuses()
                        .map_err(plugin_error)?
                        .into_iter()
                        .find(|status| status.plugin_id == plugin_id)
                        .ok_or_else(|| {
                            AtlasError::PluginError("Plugin status is unavailable".into())
                        })?;
                    let identity =
                        atlas_plugin_host::PluginIdentity::new(plugin_id, status.publisher);
                    let decision = platform.broker.authorize(&identity, &request);
                    (!decision.is_allowed())
                        .then(|| decision.code().unwrap_or("capability-denied").to_owned())
                };
                if denial_code.is_none() {
                    let request_id = secure_identifier("host-request")?;
                    let runner_request_id = runner_request_id(&request, &request_id);
                    platform.pending_host_requests.insert(
                        request_id.clone(),
                        PendingHostRequest {
                            plugin_id: plugin_id.into(),
                            command_id: command_id.into(),
                            instance_id: instance_id.into(),
                            runner_request_id,
                        },
                    );
                    events.push(plugin_runtime_event(
                        PluginHostEventKind::HostRequest,
                        plugin_id,
                        command_id,
                        instance_id,
                        None,
                        Some(request_id),
                        serde_json::json!({
                            "capability": request.capability,
                            "operation": request.operation,
                            "resource": request.resource,
                            "payload": request.payload,
                        })
                        .to_string(),
                    ));
                } else {
                    events.push(plugin_runtime_event(
                        PluginHostEventKind::Error,
                        plugin_id,
                        command_id,
                        instance_id,
                        None,
                        None,
                        serde_json::json!({
                            "code": denial_code.unwrap_or_else(|| "capability-denied".into()),
                            "message": "Capability request was denied",
                        })
                        .to_string(),
                    ));
                }
            }
            atlas_plugin_protocol::MessageKind::Log(log) => {
                platform
                    .diagnostics
                    .record(atlas_plugin_host::DiagnosticEvent {
                        plugin_id: plugin_id.into(),
                        category: atlas_plugin_host::DiagnosticCategory::Runtime,
                        command_id: Some(command_id.into()),
                        instance_id: Some(instance_id.into()),
                        version: None,
                        phase: log.target.clone(),
                        duration_millis: None,
                        error_code: None,
                        metadata: std::collections::BTreeMap::from([(
                            "level".into(),
                            format!("{:?}", log.level).to_ascii_lowercase(),
                        )]),
                        payload: Some(atlas_plugin_host::DiagnosticPayload {
                            kind: atlas_plugin_host::DiagnosticPayloadKind::Log,
                            content: log.message,
                        }),
                    })
                    .map_err(plugin_error)?;
                events.push(plugin_runtime_event(
                    PluginHostEventKind::Diagnostic,
                    plugin_id,
                    command_id,
                    instance_id,
                    None,
                    None,
                    serde_json::json!({ "category": "runtime", "target": log.target }).to_string(),
                ));
            }
            atlas_plugin_protocol::MessageKind::Metric(metric) => {
                platform
                    .supervisor
                    .record_metric(plugin_id, &metric)
                    .map_err(plugin_error)?;
            }
            atlas_plugin_protocol::MessageKind::RuntimeError(failure) => {
                let code = atlas_plugin_host::StableErrorCode::new(failure.code.clone()).ok();
                platform
                    .diagnostics
                    .record(atlas_plugin_host::DiagnosticEvent {
                        plugin_id: plugin_id.into(),
                        category: atlas_plugin_host::DiagnosticCategory::Runtime,
                        command_id: Some(command_id.into()),
                        instance_id: Some(instance_id.into()),
                        version: None,
                        phase: "adapter".into(),
                        duration_millis: None,
                        error_code: code,
                        metadata: std::collections::BTreeMap::from([(
                            "recoverable".into(),
                            failure.recoverable.to_string(),
                        )]),
                        payload: Some(atlas_plugin_host::DiagnosticPayload {
                            kind: atlas_plugin_host::DiagnosticPayloadKind::Stack,
                            content: failure.message,
                        }),
                    })
                    .map_err(plugin_error)?;
                events.push(plugin_runtime_event(
                    PluginHostEventKind::Error,
                    plugin_id,
                    command_id,
                    instance_id,
                    None,
                    None,
                    serde_json::json!({
                        "code": failure.code,
                        "message": "Plugin runtime failed",
                        "recoverable": failure.recoverable,
                    })
                    .to_string(),
                ));
            }
            atlas_plugin_protocol::MessageKind::DispatchComplete
            | atlas_plugin_protocol::MessageKind::Hello(_)
            | atlas_plugin_protocol::MessageKind::HelloAck(_)
            | atlas_plugin_protocol::MessageKind::Start(_)
            | atlas_plugin_protocol::MessageKind::Cancel
            | atlas_plugin_protocol::MessageKind::Shutdown
            | atlas_plugin_protocol::MessageKind::Health
            | atlas_plugin_protocol::MessageKind::UiEvent(_)
            | atlas_plugin_protocol::MessageKind::CapabilityResponse(_) => {}
        }
    }
    Ok(events)
}

#[cfg(feature = "executable-plugins")]
fn is_intrinsic_host_capability(capability: &str) -> bool {
    matches!(
        capability,
        "preferences.read" | "ui.alert" | "ui.hud" | "ui.toast"
    )
}

#[cfg(feature = "executable-plugins")]
fn runner_request_id(
    request: &atlas_plugin_protocol::CapabilityRequest,
    host_request_id: &str,
) -> String {
    request
        .request_id
        .clone()
        .unwrap_or_else(|| host_request_id.to_owned())
}

#[cfg(feature = "executable-plugins")]
#[allow(clippy::too_many_arguments)]
fn plugin_runtime_event(
    kind: PluginHostEventKind,
    plugin_id: &str,
    command_id: &str,
    instance_id: &str,
    session_id: Option<String>,
    request_id: Option<String>,
    payload_json: String,
) -> PluginHostEvent {
    PluginHostEvent {
        kind,
        plugin_id: plugin_id.into(),
        command_id: (!command_id.is_empty()).then(|| command_id.into()),
        instance_id: Some(instance_id.into()),
        session_id,
        request_id,
        payload_json,
    }
}

/// Starts real-time system monitoring.
///
/// This spawns a background task that collects system metrics every second
/// and pushes them to the provided callback. If monitoring is already active,
/// the existing task is stopped before starting a new one.
pub fn start_monitoring(callback: Box<dyn SystemMonitorCallback>) -> Result<(), AtlasError> {
    require_feature("monitoring")?;
    // Stop existing task if any, then release the lock before spawning (Important
    // Issue 4): holding the MutexGuard across RUNTIME.spawn() is unnecessary and
    // could deadlock if anything on the runtime thread also tries to acquire this
    // lock.
    {
        let mut handle_lock = MONITOR_HANDLE
            .lock()
            .map_err(|_| AtlasError::LockPoisoned)?;
        if let Some(handle) = handle_lock.take() {
            handle.abort();
        }
    } // lock guard is dropped here

    let callback = Arc::new(callback);

    // Critical Issue 2: the callback is a blocking synchronous FFI call; running
    // it inside spawn_blocking prevents it from starving the Tokio async worker
    // threads.
    let handle = RUNTIME.spawn(async move {
        let mut collector = atlas_core::monitor::collector::Collector::new();
        loop {
            let snapshot = collector.take_snapshot();
            let ffi_snapshot = SystemSnapshot::from(snapshot);
            let cb = Arc::clone(&callback);
            tokio::task::spawn_blocking(move || {
                cb.on_snapshot(ffi_snapshot);
            })
            .await
            .ok();
            tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
        }
    });

    MONITOR_HANDLE
        .lock()
        .map_err(|_| AtlasError::LockPoisoned)?
        .replace(handle);
    Ok(())
}

/// Stops real-time system monitoring.
pub fn stop_monitoring() -> Result<(), AtlasError> {
    let mut handle_lock = MONITOR_HANDLE
        .lock()
        .map_err(|_| AtlasError::LockPoisoned)?;
    if let Some(handle) = handle_lock.take() {
        handle.abort();
    }
    Ok(())
}

/// Looks up process information for a specific TCP port.
///
/// Returns `Ok(Some(info))` if a process is found, `Ok(None)` if no process is listening,
/// or an error if the lookup command fails.
pub fn lookup_port(port: u16) -> Result<Option<PortProcessInfo>, AtlasError> {
    require_feature("monitoring")?;
    // Critical Issue 1: previously the code unwrapped the outer Result with `?`,
    // then called `.map(|info| Ok(...)).transpose()` — redundantly wrapping an
    // already-unwrapped Option value back into Ok before transposing. The correct
    // approach maps over the outer Result and the inner Option directly.
    atlas_core::monitor::port_master::find_process_by_port(port)
        .map_err(|e| AtlasError::ProcessError(e.to_string()))
        .map(|opt| {
            opt.map(|info| PortProcessInfo {
                port: info.port,
                pid: info.pid,
                process_name: info.process_name,
            })
        })
}

/// Kills a process by its PID.
pub fn kill_port_process(pid: u32) -> Result<bool, AtlasError> {
    require_feature("monitoring")?;
    Ok(atlas_core::monitor::port_master::kill_process(pid))
}

/// Captures the full screen and returns PNG bytes.
///
/// Currently, this only supports the primary monitor.
pub fn capture_full_screen() -> Result<Vec<u8>, AtlasError> {
    require_feature("screenshot")?;
    atlas_core::capture::engine::CaptureEngine::capture_full_screen()
        .map_err(|e| AtlasError::CaptureError(e.to_string()))
}

/// Captures a specific region of the screen and returns PNG bytes.
///
/// Currently, this only supports the primary monitor.
pub fn capture_region(x: i32, y: i32, width: u32, height: u32) -> Result<Vec<u8>, AtlasError> {
    require_feature("screenshot")?;
    atlas_core::capture::engine::CaptureEngine::capture_region(x, y, width, height)
        .map_err(|e| AtlasError::CaptureError(e.to_string()))
}

/// Evaluates a mathematical expression, returning a formatted result string,
/// or `None` when the input does not evaluate to a finite number.
pub fn evaluate_expression(input: String) -> Option<String> {
    atlas_core::calculator::evaluate_expression(&input)
}

/// Returns a one-shot snapshot of the primary battery, or `None` when there is
/// no battery or it cannot be read.
pub fn current_battery() -> Option<BatterySnapshot> {
    atlas_core::monitor::battery::get_battery_info()
        .ok()
        .flatten()
        .map(|b| BatterySnapshot {
            charge_percent: b.charge_percent,
            is_charging: b.is_charging,
            time_to_empty_secs: b.time_to_empty_secs,
            time_to_full_secs: b.time_to_full_secs,
            health_percent: b.health_percent,
            cycle_count: b.cycle_count,
        })
}

pub fn search_replace_namespace(
    namespace: String,
    documents: Vec<SearchDocumentInput>,
) -> Result<(), AtlasError> {
    let namespace = namespace.trim().to_string();
    if namespace.is_empty() || namespace == "files" {
        return Err(AtlasError::SearchError(
            "namespace must be non-empty and cannot replace the file index".to_string(),
        ));
    }
    let documents = documents
        .into_iter()
        .map(|document| atlas_core::search::SearchDocument {
            id: document.id,
            namespace: namespace.clone(),
            title: document.title,
            subtitle: document.subtitle,
            keywords: document.keywords,
            path: document.path,
            kind: document.kind,
            modified_at: document.modified_at,
        })
        .collect();
    SEARCH_SERVICE
        .replace_namespace(&namespace, documents)
        .map_err(|error| AtlasError::SearchError(error.to_string()))
}

pub fn search_query(
    query: String,
    limit: u32,
    namespaces: Vec<String>,
) -> Result<Vec<SearchResultEntry>, AtlasError> {
    SEARCH_SERVICE
        .search(&query, limit.clamp(1, 200) as usize, &namespaces)
        .map(|hits| {
            hits.into_iter()
                .map(|hit| SearchResultEntry {
                    id: hit.document.id,
                    namespace: hit.document.namespace,
                    title: hit.document.title,
                    subtitle: hit.document.subtitle,
                    path: hit.document.path,
                    kind: hit.document.kind,
                    score: hit.score,
                    title_highlight_offsets: hit.title_highlight_offsets,
                })
                .collect()
        })
        .map_err(|error| AtlasError::SearchError(error.to_string()))
}

pub fn search_rank_documents(
    query: String,
    documents: Vec<SearchDocumentInput>,
    limit: u32,
) -> Result<Vec<SearchResultEntry>, AtlasError> {
    let documents = documents
        .into_iter()
        .map(|document| atlas_core::search::SearchDocument {
            id: document.id,
            namespace: document.namespace,
            title: document.title,
            subtitle: document.subtitle,
            keywords: document.keywords,
            path: document.path,
            kind: document.kind,
            modified_at: document.modified_at,
        })
        .collect();
    atlas_core::search::rank_documents(documents, &query, limit.clamp(1, 50_000) as usize)
        .map(|hits| {
            hits.into_iter()
                .map(|hit| SearchResultEntry {
                    id: hit.document.id,
                    namespace: hit.document.namespace,
                    title: hit.document.title,
                    subtitle: hit.document.subtitle,
                    path: hit.document.path,
                    kind: hit.document.kind,
                    score: hit.score,
                    title_highlight_offsets: hit.title_highlight_offsets,
                })
                .collect()
        })
        .map_err(|error| AtlasError::SearchError(error.to_string()))
}

pub fn file_index_start(roots: Vec<String>, cache_path: String) -> Result<(), AtlasError> {
    SEARCH_SERVICE
        .start_file_index(
            roots.into_iter().map(std::path::PathBuf::from).collect(),
            std::path::PathBuf::from(cache_path),
        )
        .map_err(|error| AtlasError::SearchError(error.to_string()))
}

pub fn file_index_stop() -> Result<(), AtlasError> {
    SEARCH_SERVICE
        .stop_file_index()
        .map_err(|error| AtlasError::SearchError(error.to_string()))
}

pub fn file_index_status() -> Result<SearchIndexStatus, AtlasError> {
    SEARCH_SERVICE
        .file_status()
        .map(|status| SearchIndexStatus {
            phase: match status.phase {
                atlas_core::search::FileIndexPhase::Idle => SearchIndexPhase::Idle,
                atlas_core::search::FileIndexPhase::Loading => SearchIndexPhase::Loading,
                atlas_core::search::FileIndexPhase::Scanning => SearchIndexPhase::Scanning,
                atlas_core::search::FileIndexPhase::Ready => SearchIndexPhase::Ready,
                atlas_core::search::FileIndexPhase::Error => SearchIndexPhase::Error,
            },
            indexed_count: status.indexed_count,
            last_error: status.last_error,
        })
        .map_err(|error| AtlasError::SearchError(error.to_string()))
}

#[cfg(test)]
#[allow(clippy::items_after_test_module)]
mod tests {
    use super::*;

    static TEST_LOCK: Lazy<Mutex<()>> = Lazy::new(|| Mutex::new(()));

    #[cfg(feature = "executable-plugins")]
    #[test]
    fn intrinsic_host_capabilities_and_runtime_request_ids_are_preserved() {
        assert!(is_intrinsic_host_capability("ui.toast"));
        assert!(is_intrinsic_host_capability("preferences.read"));
        assert!(!is_intrinsic_host_capability("clipboard.read"));

        let request = atlas_plugin_protocol::CapabilityRequest {
            request_id: Some("atlas-1".into()),
            capability: "ui.toast".into(),
            operation: "toast".into(),
            resource: None,
            payload: Vec::new(),
        };
        assert_eq!(runner_request_id(&request, "host-request-1"), "atlas-1");
    }

    #[test]
    fn test_get_core_status() {
        let _guard = TEST_LOCK.lock().unwrap();
        let status = get_core_status().unwrap();
        assert!(status.contains("Atlas Core v"));
        assert!(status.contains("is running"));
    }

    #[test]
    fn test_feature_management() {
        let _guard = TEST_LOCK.lock().unwrap();
        configure_entitlement(CoreEdition::Free).unwrap();
        let features = list_features().unwrap();
        let names: Vec<_> = features.iter().map(|f| f.name.as_str()).collect();

        assert!(features.iter().any(|f| f.name == "ai-load-monitor"));
        assert!(features.iter().any(|f| f.name == "automation"));
        assert!(features.iter().any(|f| f.name == "monitoring"));
        assert!(features.iter().any(|f| f.name == "scratchpad"));
        assert!(features.iter().any(|f| f.name == "screenshot"));
        assert!(features.iter().any(|f| f.name == "tokenbar"));
        assert!(features.iter().any(|f| f.name == "window-manager"));
        assert!(names.windows(2).all(|pair| pair[0] <= pair[1]));

        assert!(toggle_feature("monitoring".to_string(), true).unwrap());
        let features = list_features().unwrap();
        let monitoring = features
            .iter()
            .find(|f| f.name == "monitoring")
            .expect("monitoring feature should exist");
        assert!(matches!(monitoring.status, FeatureStatus::Enabled));

        assert!(!toggle_feature("non-existent".to_string(), true).unwrap());

        assert!(toggle_feature("monitoring".to_string(), false).unwrap());
        let features = list_features().unwrap();
        let monitoring = features
            .iter()
            .find(|f| f.name == "monitoring")
            .expect("monitoring feature should exist");
        assert!(matches!(monitoring.status, FeatureStatus::Disabled));
    }

    #[test]
    fn test_port_lookup() {
        let _guard = TEST_LOCK.lock().unwrap();
        configure_entitlement(CoreEdition::Free).unwrap();
        toggle_feature("monitoring".to_string(), true).unwrap();
        use std::net::TcpListener;
        // Bind to an ephemeral port to test lookup
        let listener = TcpListener::bind("127.0.0.1:0").expect("Failed to bind");
        let port = listener.local_addr().unwrap().port();

        let info = lookup_port(port).unwrap();
        assert!(info.is_some());
        let info = info.unwrap();
        assert_eq!(info.port, port);
        assert!(info.pid > 0);
    }

    #[test]
    fn test_capture_functions_exist() {
        let _guard = TEST_LOCK.lock().unwrap();
        configure_entitlement(CoreEdition::Free).unwrap();
        toggle_feature("screenshot".to_string(), true).unwrap();
        // In CI, these will likely return error in headless environment,
        // but we want to ensure they are callable and return Result.
        let _ = capture_full_screen();
        let _ = capture_region(0, 0, 100, 100);
    }

    #[test]
    fn test_core_rejects_disabled_feature_operations() {
        let _guard = TEST_LOCK.lock().unwrap();
        toggle_feature("screenshot".to_string(), false).unwrap();
        assert!(matches!(
            capture_full_screen(),
            Err(AtlasError::FeatureDisabled(name)) if name == "screenshot"
        ));
    }

    #[test]
    fn test_core_enforces_entitlement() {
        let _guard = TEST_LOCK.lock().unwrap();
        configure_entitlement(CoreEdition::Free).unwrap();
        assert!(matches!(
            toggle_feature("window-manager".to_string(), true),
            Err(AtlasError::EntitlementDenied(_))
        ));

        configure_entitlement(CoreEdition::Pro).unwrap();
        assert!(toggle_feature("window-manager".to_string(), true).unwrap());
    }

    #[test]
    fn legacy_plugin_execution_is_disabled() {
        let error = match install_js_plugin(String::new(), String::new(), String::new()) {
            Ok(_) => panic!("legacy plugin unexpectedly installed"),
            Err(error) => error,
        };
        assert!(error
            .to_string()
            .contains("Legacy in-process plugin execution is disabled"));
        assert!(list_plugins().unwrap().is_empty());
    }

    #[cfg(feature = "executable-plugins")]
    #[test]
    fn test_plugin_manifest_preview_exposes_requested_capabilities() {
        let preview = inspect_plugin_manifest(
            r#"
            name = "translator"
            version = "1.2.3"
            [capabilities]
            network = ["api.example.com"]
            storage = true
            clipboard = true
            webview = true
            webview_bridge = true
            exposed_tools = ["translate"]
            "#
            .to_string(),
        )
        .unwrap();

        assert_eq!(preview.name, "translator");
        assert_eq!(preview.version, "1.2.3");
        assert_eq!(preview.network_hosts, ["api.example.com"]);
        assert!(preview.storage);
        assert!(preview.clipboard);
        assert!(preview.webview);
        assert!(preview.webview_bridge);
        assert_eq!(preview.exposed_tools, ["translate"]);
    }

    #[cfg(feature = "executable-plugins")]
    #[test]
    fn plugin_platform_install_emits_consent_before_activation() {
        use std::io::Write;

        let _guard = TEST_LOCK.lock().unwrap();
        let directory = tempfile::tempdir().unwrap();
        initialize_plugin_storage(
            directory.path().to_string_lossy().into_owned(),
            vec![0x61; 32],
        )
        .unwrap();
        let recorded = Arc::new(Mutex::new(Vec::new()));
        plugin_platform_start(Box::new(RecordingPluginCallback(Arc::clone(&recorded)))).unwrap();

        let staged = plugin_stage_package(plugin_fixture_archive()).unwrap();
        assert!(matches!(staged.state, PluginStageState::AwaitingConsent));
        assert!(plugin_platform_statuses().unwrap().is_empty());
        let events = recorded.lock().unwrap();
        assert_eq!(events.len(), 1);
        assert!(matches!(
            events[0].kind,
            PluginHostEventKind::ConsentRequired
        ));
        assert_eq!(
            events[0].request_id.as_deref(),
            Some(staged.stage_id.as_str())
        );

        fn plugin_fixture_archive() -> Vec<u8> {
            let manifest = atlas_plugin_package::PluginManifestV2 {
                manifest_version: 2,
                id: "dev.example.ffi-platform".into(),
                name: "FFI Platform".into(),
                version: "1.0.0".into(),
                publisher: "Example".into(),
                runtime: atlas_plugin_package::RuntimeKind::Wasm,
                entrypoint: "payload/main.wasm".into(),
                storage_schema: 1,
                capabilities: vec!["storage.kv".into()],
                trust: None,
            };
            let mut files = std::collections::BTreeMap::from([
                (
                    "plugin.toml".to_string(),
                    toml::to_string(&manifest).unwrap().into_bytes(),
                ),
                (
                    "permissions.json".to_string(),
                    serde_json::to_vec(&manifest.capabilities).unwrap(),
                ),
                ("payload/main.wasm".to_string(), b"fixture".to_vec()),
            ]);
            let records = files
                .iter()
                .map(|(path, bytes)| atlas_plugin_package::IntegrityFile {
                    path: path.clone(),
                    length: bytes.len() as u64,
                    sha256: atlas_plugin_package::sha256_digest(bytes)
                        .iter()
                        .map(|byte| format!("{byte:02x}"))
                        .collect(),
                })
                .collect();
            files.insert(
                "integrity.json".into(),
                serde_json::to_vec(&atlas_plugin_package::IntegrityDocument::new(records).unwrap())
                    .unwrap(),
            );
            let mut archive = std::io::Cursor::new(Vec::new());
            {
                let mut writer = zip::ZipWriter::new(&mut archive);
                for (path, bytes) in files {
                    writer
                        .start_file(path, zip::write::SimpleFileOptions::default())
                        .unwrap();
                    writer.write_all(&bytes).unwrap();
                }
                writer.finish().unwrap();
            }
            archive.into_inner()
        }
    }

    #[cfg(feature = "executable-plugins")]
    struct RecordingPluginCallback(Arc<Mutex<Vec<PluginHostEvent>>>);

    #[cfg(feature = "executable-plugins")]
    impl PluginPlatformCallback for RecordingPluginCallback {
        fn on_plugin_event(&self, event: PluginHostEvent) {
            self.0.lock().unwrap().push(event);
        }
    }
}

// MARK: - AI center

static AI_STORE: Lazy<Mutex<Option<atlas_ai::AiStore>>> = Lazy::new(|| Mutex::new(None));
static AI_REQUESTS: Lazy<
    Mutex<std::collections::HashMap<u64, tokio_util::sync::CancellationToken>>,
> = Lazy::new(|| Mutex::new(std::collections::HashMap::new()));
static AI_REQUEST_COUNTER: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);

pub struct AiProviderConfig {
    pub id: String,
    pub name: String,
    pub base_url: String,
    pub model: String,
    pub max_tokens: Option<u32>,
}

pub struct AiDetectedCli {
    pub kind_id: String,
    pub display: String,
    pub subtitle: String,
    pub path: String,
    pub version: String,
    pub default_models: Vec<String>,
}

pub struct AiChatMessage {
    pub id: String,
    pub role: String,
    pub text: String,
    pub image_paths: Vec<String>,
    pub timestamp_ms: i64,
    pub error: Option<String>,
}

pub struct AiSessionSummary {
    pub id: String,
    pub title: String,
    pub created_at_ms: i64,
    pub message_count: u32,
}

pub struct AiChatSession {
    pub id: String,
    pub title: String,
    pub created_at_ms: i64,
    pub preset_id: Option<String>,
    pub provider_id: Option<String>,
    pub messages: Vec<AiChatMessage>,
}

pub struct AiPromptPreset {
    pub id: String,
    pub name: String,
    pub system_prompt: String,
}

pub trait AiChatStreamDelegate: Send + Sync {
    fn on_delta(&self, request_id: u64, text: String);
    fn on_done(&self, request_id: u64);
    fn on_error(&self, request_id: u64, message: String);
}

impl From<atlas_ai::AiError> for AtlasError {
    fn from(error: atlas_ai::AiError) -> Self {
        AtlasError::AiError(error.to_string())
    }
}

impl From<atlas_ai::ProviderConfig> for AiProviderConfig {
    fn from(p: atlas_ai::ProviderConfig) -> Self {
        Self {
            id: p.id,
            name: p.name,
            base_url: p.base_url,
            model: p.model,
            max_tokens: p.max_tokens,
        }
    }
}

impl From<AiProviderConfig> for atlas_ai::ProviderConfig {
    fn from(p: AiProviderConfig) -> Self {
        Self {
            id: p.id,
            name: p.name,
            base_url: p.base_url,
            model: p.model,
            extra_headers: vec![],
            max_tokens: p.max_tokens,
        }
    }
}

impl From<atlas_ai::DetectedCli> for AiDetectedCli {
    fn from(c: atlas_ai::DetectedCli) -> Self {
        Self {
            kind_id: c.kind_id,
            display: c.display,
            subtitle: c.subtitle,
            path: c.path,
            version: c.version,
            default_models: c.default_models,
        }
    }
}

impl From<atlas_ai::ChatMessage> for AiChatMessage {
    fn from(m: atlas_ai::ChatMessage) -> Self {
        Self {
            id: m.id,
            role: m.role.as_str().to_string(),
            text: m.text,
            image_paths: m.image_paths,
            timestamp_ms: m.timestamp_ms,
            error: m.error,
        }
    }
}

impl From<AiChatMessage> for atlas_ai::ChatMessage {
    fn from(m: AiChatMessage) -> Self {
        Self {
            id: m.id,
            role: atlas_ai::ChatRole::parse(&m.role),
            text: m.text,
            image_paths: m.image_paths,
            timestamp_ms: m.timestamp_ms,
            error: m.error,
        }
    }
}

impl From<atlas_ai::ChatSession> for AiChatSession {
    fn from(s: atlas_ai::ChatSession) -> Self {
        Self {
            id: s.id,
            title: s.title,
            created_at_ms: s.created_at_ms,
            preset_id: s.preset_id,
            provider_id: s.provider_id,
            messages: s.messages.into_iter().map(Into::into).collect(),
        }
    }
}

impl From<AiChatSession> for atlas_ai::ChatSession {
    fn from(s: AiChatSession) -> Self {
        Self {
            id: s.id,
            title: s.title,
            created_at_ms: s.created_at_ms,
            preset_id: s.preset_id,
            provider_id: s.provider_id,
            messages: s.messages.into_iter().map(Into::into).collect(),
        }
    }
}

impl From<atlas_ai::SessionSummary> for AiSessionSummary {
    fn from(s: atlas_ai::SessionSummary) -> Self {
        Self {
            id: s.id,
            title: s.title,
            created_at_ms: s.created_at_ms,
            message_count: s.message_count,
        }
    }
}

impl From<atlas_ai::PromptPreset> for AiPromptPreset {
    fn from(p: atlas_ai::PromptPreset) -> Self {
        Self {
            id: p.id,
            name: p.name,
            system_prompt: p.system_prompt,
        }
    }
}

impl From<AiPromptPreset> for atlas_ai::PromptPreset {
    fn from(p: AiPromptPreset) -> Self {
        Self {
            id: p.id,
            name: p.name,
            system_prompt: p.system_prompt,
        }
    }
}

fn with_ai_store<T>(
    f: impl FnOnce(&atlas_ai::AiStore) -> Result<T, atlas_ai::AiError>,
) -> Result<T, AtlasError> {
    let guard = AI_STORE.lock().map_err(|_| AtlasError::LockPoisoned)?;
    let store = guard
        .as_ref()
        .ok_or_else(|| AtlasError::AiError("storage dir not set".to_string()))?;
    f(store).map_err(Into::into)
}

pub fn ai_set_storage_dir(path: String) {
    if let Ok(store) = atlas_ai::AiStore::new(&path) {
        if let Ok(mut guard) = AI_STORE.lock() {
            *guard = Some(store);
        }
    }
}

pub fn ai_list_providers() -> Result<Vec<AiProviderConfig>, AtlasError> {
    with_ai_store(|s| s.providers()).map(|v| v.into_iter().map(Into::into).collect())
}

pub fn ai_save_provider(provider: AiProviderConfig) -> Result<(), AtlasError> {
    let provider: atlas_ai::ProviderConfig = provider.into();
    with_ai_store(|s| s.save_provider(&provider))
}

pub fn ai_delete_provider(id: String) -> Result<(), AtlasError> {
    with_ai_store(|s| s.delete_provider(&id))
}

pub fn ai_list_sessions() -> Result<Vec<AiSessionSummary>, AtlasError> {
    with_ai_store(|s| s.sessions_index()).map(|v| v.into_iter().map(Into::into).collect())
}

pub fn ai_load_session(id: String) -> Result<AiChatSession, AtlasError> {
    with_ai_store(|s| s.load_session(&id)).map(Into::into)
}

pub fn ai_save_session(session: AiChatSession) -> Result<(), AtlasError> {
    let session: atlas_ai::ChatSession = session.into();
    with_ai_store(|s| s.save_session(&session))
}

pub fn ai_delete_session(id: String) -> Result<(), AtlasError> {
    with_ai_store(|s| s.delete_session(&id))
}

pub fn ai_list_presets() -> Result<Vec<AiPromptPreset>, AtlasError> {
    with_ai_store(|s| s.presets()).map(|v| v.into_iter().map(Into::into).collect())
}

pub fn ai_save_preset(preset: AiPromptPreset) -> Result<(), AtlasError> {
    let preset: atlas_ai::PromptPreset = preset.into();
    with_ai_store(|s| s.save_preset(&preset))
}

pub fn ai_delete_preset(id: String) -> Result<(), AtlasError> {
    with_ai_store(|s| s.delete_preset(&id))
}

pub fn ai_export_session_markdown(id: String) -> Result<String, AtlasError> {
    with_ai_store(|s| s.load_session(&id)).map(|session| atlas_ai::export_markdown(&session))
}

struct DelegateSink {
    request_id: u64,
    delegate: Box<dyn AiChatStreamDelegate>,
}

impl atlas_ai::StreamSink for DelegateSink {
    fn on_delta(&self, text: String) {
        self.delegate.on_delta(self.request_id, text);
    }
    fn on_done(&self) {
        let _ = AI_REQUESTS
            .lock()
            .map(|mut map| map.remove(&self.request_id));
        self.delegate.on_done(self.request_id);
    }
    fn on_error(&self, message: String) {
        let _ = AI_REQUESTS
            .lock()
            .map(|mut map| map.remove(&self.request_id));
        self.delegate.on_error(self.request_id, message);
    }
}

pub fn ai_send_message(
    session_id: String,
    provider: AiProviderConfig,
    api_key: String,
    system_prompt: Option<String>,
    delegate: Box<dyn AiChatStreamDelegate>,
) -> Result<u64, AtlasError> {
    let session = with_ai_store(|s| s.load_session(&session_id))?;
    let provider: atlas_ai::ProviderConfig = provider.into();

    let request = atlas_ai::SendRequest {
        base_url: provider.base_url,
        api_key,
        model: provider.model,
        extra_headers: provider.extra_headers,
        system_prompt,
        messages: session.messages,
        max_tokens: provider.max_tokens,
    };

    let request_id = AI_REQUEST_COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let cancel = tokio_util::sync::CancellationToken::new();
    AI_REQUESTS
        .lock()
        .map_err(|_| AtlasError::LockPoisoned)?
        .insert(request_id, cancel.clone());

    let sink = std::sync::Arc::new(DelegateSink {
        request_id,
        delegate,
    });
    RUNTIME.spawn(async move {
        atlas_ai::send_streaming(request, sink, cancel).await;
    });

    Ok(request_id)
}

pub fn ai_cancel(request_id: u64) {
    if let Ok(map) = AI_REQUESTS.lock() {
        if let Some(token) = map.get(&request_id) {
            token.cancel();
        }
    }
}

pub fn ai_detect_clis(search_dirs: Vec<String>) -> Vec<AiDetectedCli> {
    atlas_ai::detect_clis(&search_dirs)
        .into_iter()
        .map(Into::into)
        .collect()
}

pub fn ai_send_via_cli(
    session_id: String,
    cli_id: String,
    cli_path: String,
    model: Option<String>,
    delegate: Box<dyn AiChatStreamDelegate>,
) -> Result<u64, AtlasError> {
    let session = with_ai_store(|s| s.load_session(&session_id))?;
    // Local CLIs are single-turn: send the latest user message as the prompt.
    let prompt = session
        .messages
        .iter()
        .rev()
        .find(|message| message.role == atlas_ai::ChatRole::User)
        .map(|message| message.text.clone())
        .ok_or_else(|| AtlasError::AiError("session has no user message".to_string()))?;

    let request_id = AI_REQUEST_COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let cancel = tokio_util::sync::CancellationToken::new();
    AI_REQUESTS
        .lock()
        .map_err(|_| AtlasError::LockPoisoned)?
        .insert(request_id, cancel.clone());

    let sink = std::sync::Arc::new(DelegateSink {
        request_id,
        delegate,
    });
    RUNTIME.spawn(async move {
        atlas_ai::run_prompt_via_cli(&cli_id, &cli_path, model, prompt, sink, cancel).await;
    });

    Ok(request_id)
}

// MARK: - Notes / Focus / Transfer / AI Commands

static NOTES_STORE: Lazy<Mutex<Option<atlas_core::notes::NotesStore>>> =
    Lazy::new(|| Mutex::new(None));
static FOCUS_STORE: Lazy<Mutex<Option<atlas_core::focus::FocusStore>>> =
    Lazy::new(|| Mutex::new(None));
static AI_COMMAND_STORE: Lazy<Mutex<Option<atlas_ai::AiCommandStore>>> =
    Lazy::new(|| Mutex::new(None));

pub struct NoteMeta {
    pub id: String,
    pub title: String,
    pub pinned: bool,
    pub created_at: u64,
    pub updated_at: u64,
}

pub struct NoteContent {
    pub meta: NoteMeta,
    pub body_md: String,
}

pub struct FocusConfig {
    pub goal: String,
    pub duration_min: u32,
    pub blocked_bundle_ids: Vec<String>,
    pub enable_dnd: bool,
}

pub enum FocusPhase {
    Idle,
    Running,
    Paused,
}

pub struct FocusStatus {
    pub phase: FocusPhase,
    pub config: Option<FocusConfig>,
    pub remaining_secs: u64,
}

pub struct FocusSessionRecord {
    pub goal: String,
    pub duration_min: u32,
    pub started_at: u64,
    pub ended_at: u64,
    pub completed: bool,
}

pub struct TransferPayload {
    pub kind: String,
    pub json: String,
}

pub struct TransferManifest {
    pub version: u32,
    pub exported_at: u64,
    pub kinds: Vec<String>,
}

pub enum AiCommandOutputMode {
    Panel,
    Paste,
    Copy,
}

pub struct AiCommandEntry {
    pub id: String,
    pub name: String,
    pub icon: String,
    pub prompt_template: String,
    pub output: AiCommandOutputMode,
    pub builtin: bool,
}

impl From<atlas_core::notes::NoteMeta> for NoteMeta {
    fn from(m: atlas_core::notes::NoteMeta) -> Self {
        Self {
            id: m.id,
            title: m.title,
            pinned: m.pinned,
            created_at: m.created_at,
            updated_at: m.updated_at,
        }
    }
}

impl From<atlas_core::focus::FocusConfig> for FocusConfig {
    fn from(c: atlas_core::focus::FocusConfig) -> Self {
        Self {
            goal: c.goal,
            duration_min: c.duration_min,
            blocked_bundle_ids: c.blocked_bundle_ids,
            enable_dnd: c.enable_dnd,
        }
    }
}

impl From<FocusConfig> for atlas_core::focus::FocusConfig {
    fn from(c: FocusConfig) -> Self {
        Self {
            goal: c.goal,
            duration_min: c.duration_min,
            blocked_bundle_ids: c.blocked_bundle_ids,
            enable_dnd: c.enable_dnd,
        }
    }
}

impl From<atlas_ai::AiCommandOutput> for AiCommandOutputMode {
    fn from(o: atlas_ai::AiCommandOutput) -> Self {
        match o {
            atlas_ai::AiCommandOutput::Panel => Self::Panel,
            atlas_ai::AiCommandOutput::Paste => Self::Paste,
            atlas_ai::AiCommandOutput::Copy => Self::Copy,
        }
    }
}

impl From<AiCommandOutputMode> for atlas_ai::AiCommandOutput {
    fn from(o: AiCommandOutputMode) -> Self {
        match o {
            AiCommandOutputMode::Panel => Self::Panel,
            AiCommandOutputMode::Paste => Self::Paste,
            AiCommandOutputMode::Copy => Self::Copy,
        }
    }
}

impl From<atlas_ai::AiCommand> for AiCommandEntry {
    fn from(c: atlas_ai::AiCommand) -> Self {
        Self {
            id: c.id,
            name: c.name,
            icon: c.icon,
            prompt_template: c.prompt_template,
            output: c.output.into(),
            builtin: c.builtin,
        }
    }
}

impl From<AiCommandEntry> for atlas_ai::AiCommand {
    fn from(c: AiCommandEntry) -> Self {
        Self {
            id: c.id,
            name: c.name,
            icon: c.icon,
            prompt_template: c.prompt_template,
            output: c.output.into(),
            builtin: c.builtin,
        }
    }
}

impl From<atlas_core::notes::NotesError> for AtlasError {
    fn from(error: atlas_core::notes::NotesError) -> Self {
        AtlasError::AiError(error.to_string())
    }
}

impl From<atlas_core::focus::FocusError> for AtlasError {
    fn from(error: atlas_core::focus::FocusError) -> Self {
        AtlasError::AiError(error.to_string())
    }
}

impl From<atlas_core::transfer::TransferError> for AtlasError {
    fn from(error: atlas_core::transfer::TransferError) -> Self {
        AtlasError::AiError(error.to_string())
    }
}

fn focus_status_from(state: atlas_core::focus::FocusState, remaining: u64) -> FocusStatus {
    match state {
        atlas_core::focus::FocusState::Idle => FocusStatus {
            phase: FocusPhase::Idle,
            config: None,
            remaining_secs: 0,
        },
        atlas_core::focus::FocusState::Running { config, .. } => FocusStatus {
            phase: FocusPhase::Running,
            config: Some(config.into()),
            remaining_secs: remaining,
        },
        atlas_core::focus::FocusState::Paused {
            config,
            remaining_secs,
            ..
        } => FocusStatus {
            phase: FocusPhase::Paused,
            config: Some(config.into()),
            remaining_secs,
        },
    }
}

fn with_notes_store<T>(
    f: impl FnOnce(&atlas_core::notes::NotesStore) -> Result<T, atlas_core::notes::NotesError>,
) -> Result<T, AtlasError> {
    let guard = NOTES_STORE.lock().map_err(|_| AtlasError::LockPoisoned)?;
    let store = guard
        .as_ref()
        .ok_or_else(|| AtlasError::AiError("notes storage dir not set".to_string()))?;
    f(store).map_err(Into::into)
}

fn with_focus_store<T>(
    f: impl FnOnce(&atlas_core::focus::FocusStore) -> Result<T, atlas_core::focus::FocusError>,
) -> Result<T, AtlasError> {
    let guard = FOCUS_STORE.lock().map_err(|_| AtlasError::LockPoisoned)?;
    let store = guard
        .as_ref()
        .ok_or_else(|| AtlasError::AiError("focus storage dir not set".to_string()))?;
    f(store).map_err(Into::into)
}

fn with_ai_command_store<T>(
    f: impl FnOnce(&atlas_ai::AiCommandStore) -> Result<T, atlas_ai::AiError>,
) -> Result<T, AtlasError> {
    let guard = AI_COMMAND_STORE
        .lock()
        .map_err(|_| AtlasError::LockPoisoned)?;
    let store = guard
        .as_ref()
        .ok_or_else(|| AtlasError::AiError("ai storage dir not set".to_string()))?;
    f(store).map_err(Into::into)
}

pub fn notes_set_storage_dir(path: String) {
    if let Ok(store) = atlas_core::notes::NotesStore::new(&path) {
        if let Ok(mut guard) = NOTES_STORE.lock() {
            *guard = Some(store);
        }
    }
}

pub fn notes_list() -> Result<Vec<NoteMeta>, AtlasError> {
    with_notes_store(|s| s.list()).map(|v| v.into_iter().map(Into::into).collect())
}

pub fn notes_get(id: String) -> Result<NoteContent, AtlasError> {
    with_notes_store(|s| s.get(&id)).map(|n| NoteContent {
        meta: n.meta.into(),
        body_md: n.body_md,
    })
}

pub fn notes_save(
    id: Option<String>,
    title: String,
    body_md: String,
) -> Result<String, AtlasError> {
    with_notes_store(|s| s.save(id.as_deref(), &title, &body_md))
}

pub fn notes_delete(id: String) -> Result<(), AtlasError> {
    with_notes_store(|s| s.delete(&id))
}

pub fn notes_toggle_pin(id: String) -> Result<bool, AtlasError> {
    with_notes_store(|s| s.toggle_pin(&id))
}

pub fn notes_search(query: String) -> Result<Vec<NoteMeta>, AtlasError> {
    with_notes_store(|s| s.search(&query)).map(|v| v.into_iter().map(Into::into).collect())
}

pub fn focus_set_storage_dir(path: String) {
    if let Ok(store) = atlas_core::focus::FocusStore::new(&path) {
        if let Ok(mut guard) = FOCUS_STORE.lock() {
            *guard = Some(store);
        }
    }
}

pub fn focus_start(config: FocusConfig) -> Result<FocusStatus, AtlasError> {
    let config: atlas_core::focus::FocusConfig = config.into();
    let state = with_focus_store(|s| s.start(config))?;
    let remaining = with_focus_store(|s| s.remaining_secs())?;
    Ok(focus_status_from(state, remaining))
}

pub fn focus_pause() -> Result<FocusStatus, AtlasError> {
    let state = with_focus_store(|s| s.pause())?;
    Ok(focus_status_from(state, 0))
}

pub fn focus_resume() -> Result<FocusStatus, AtlasError> {
    let state = with_focus_store(|s| s.resume())?;
    let remaining = with_focus_store(|s| s.remaining_secs())?;
    Ok(focus_status_from(state, remaining))
}

pub fn focus_stop() -> Result<(), AtlasError> {
    with_focus_store(|s| s.stop())
}

pub fn focus_state() -> Result<FocusStatus, AtlasError> {
    let state = with_focus_store(|s| s.state())?;
    let remaining = with_focus_store(|s| s.remaining_secs())?;
    Ok(focus_status_from(state, remaining))
}

pub fn focus_history() -> Result<Vec<FocusSessionRecord>, AtlasError> {
    with_focus_store(|s| s.history()).map(|v| {
        v.into_iter()
            .map(|r| FocusSessionRecord {
                goal: r.goal,
                duration_min: r.duration_min,
                started_at: r.started_at,
                ended_at: r.ended_at,
                completed: r.completed,
            })
            .collect()
    })
}

pub fn transfer_export(
    payloads: Vec<TransferPayload>,
    dest_path: String,
) -> Result<TransferManifest, AtlasError> {
    let payloads: Vec<atlas_core::transfer::TransferPayload> = payloads
        .into_iter()
        .map(|p| atlas_core::transfer::TransferPayload {
            kind: p.kind,
            json: p.json,
        })
        .collect();
    let manifest = atlas_core::transfer::export(&payloads, std::path::Path::new(&dest_path))?;
    Ok(TransferManifest {
        version: manifest.version,
        exported_at: manifest.exported_at,
        kinds: manifest.kinds,
    })
}

pub fn transfer_inspect(path: String) -> Result<TransferManifest, AtlasError> {
    let manifest = atlas_core::transfer::inspect(std::path::Path::new(&path))?;
    Ok(TransferManifest {
        version: manifest.version,
        exported_at: manifest.exported_at,
        kinds: manifest.kinds,
    })
}

pub fn transfer_import(
    path: String,
    kinds: Vec<String>,
) -> Result<Vec<TransferPayload>, AtlasError> {
    let payloads = atlas_core::transfer::import(std::path::Path::new(&path), &kinds)?;
    Ok(payloads
        .into_iter()
        .map(|p| TransferPayload {
            kind: p.kind,
            json: p.json,
        })
        .collect())
}

pub fn ai_commands_list() -> Result<Vec<AiCommandEntry>, AtlasError> {
    ensure_ai_command_store();
    with_ai_command_store(|s| s.list()).map(|v| v.into_iter().map(Into::into).collect())
}

pub fn ai_commands_save(command: AiCommandEntry) -> Result<(), AtlasError> {
    ensure_ai_command_store();
    let command: atlas_ai::AiCommand = command.into();
    with_ai_command_store(|s| s.save(&command))
}

pub fn ai_commands_delete(id: String) -> Result<(), AtlasError> {
    ensure_ai_command_store();
    with_ai_command_store(|s| s.delete(&id))
}

pub fn ai_commands_render(template: String, selection: String) -> String {
    atlas_ai::render_prompt(&template, &selection)
}

/// AI 指令库与 AiStore 同根:ai_set_storage_dir 已注入时惰性建店。
fn ensure_ai_command_store() {
    if let Ok(mut guard) = AI_COMMAND_STORE.lock() {
        if guard.is_none() {
            if let Ok(store_guard) = AI_STORE.lock() {
                if let Some(ai_store) = store_guard.as_ref() {
                    if let Ok(store) = atlas_ai::AiCommandStore::new(ai_store.root_dir()) {
                        *guard = Some(store);
                    }
                }
            }
        }
    }
}

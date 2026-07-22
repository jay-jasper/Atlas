//! Atlas FFI Crate
//!
//! This crate provides a Foreign Function Interface (FFI) for the Atlas core functionality,
//! allowing it to be used from other languages via UniFFI.

// UniFFI's UDL scaffolding generates a separated doc comment. Keep strict
// Clippy enabled for handwritten code while tolerating that upstream output.
#![allow(clippy::empty_line_after_doc_comments)]

use atlas_core::AtlasCore;
use once_cell::sync::Lazy;
use std::sync::{Arc, Mutex};
use thiserror::Error;
use tokio::runtime::Runtime;
use tokio::task::JoinHandle;

uniffi::include_scaffolding!("atlas");

/// Global instance of the Atlas core to preserve state across FFI calls.
static CORE: Lazy<Mutex<AtlasCore>> = Lazy::new(|| Mutex::new(AtlasCore::new()));
#[cfg(feature = "executable-plugins")]
static PLUGIN_HOST: Lazy<Mutex<atlas_plugin_host::PluginRuntimeHost>> =
    Lazy::new(|| Mutex::new(atlas_plugin_host::PluginRuntimeHost::new()));

/// Control the monitoring background task.
static MONITOR_HANDLE: Lazy<Mutex<Option<JoinHandle<()>>>> = Lazy::new(|| Mutex::new(None));

/// Global Tokio runtime for background tasks.
static RUNTIME: Lazy<Runtime> =
    Lazy::new(|| Runtime::new().expect("Failed to create Tokio runtime"));

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

#[cfg(feature = "executable-plugins")]
impl From<atlas_plugin_host::PluginRuntimeEntry> for PluginEntry {
    fn from(entry: atlas_plugin_host::PluginRuntimeEntry) -> Self {
        Self {
            id: entry.id,
            name: entry.name,
            version: entry.version,
            runtime: match entry.runtime {
                atlas_plugin_host::RuntimeKind::Wasm => PluginRuntime::Wasm,
                atlas_plugin_host::RuntimeKind::Mcp => PluginRuntime::Mcp,
                atlas_plugin_host::RuntimeKind::Js => PluginRuntime::Js,
            },
            ui_json: entry.ui_json,
        }
    }
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
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = (manifest_toml, wasm_bytes, ui_json);
        Err(AtlasError::PluginError(
            "Executable plugins are unavailable in this distribution".to_string(),
        ))
    }
    #[cfg(feature = "executable-plugins")]
    {
        PLUGIN_HOST
            .lock()
            .map_err(|_| AtlasError::LockPoisoned)?
            .install_wasm(&manifest_toml, &wasm_bytes, &ui_json)
            .map(PluginEntry::from)
            .map_err(|error| AtlasError::PluginError(error.to_string()))
    }
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
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = (manifest_toml, ui_json);
        Err(AtlasError::PluginError(
            "Executable plugins are unavailable in this distribution".to_string(),
        ))
    }
    #[cfg(feature = "executable-plugins")]
    {
        PLUGIN_HOST
            .lock()
            .map_err(|_| AtlasError::LockPoisoned)?
            .install_mcp(&manifest_toml, &ui_json)
            .map(PluginEntry::from)
            .map_err(|error| AtlasError::PluginError(error.to_string()))
    }
}

pub fn install_js_plugin(
    manifest_toml: String,
    source: String,
    ui_json: String,
) -> Result<PluginEntry, AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = (manifest_toml, source, ui_json);
        Err(AtlasError::PluginError(
            "Executable plugins are unavailable in this distribution".to_string(),
        ))
    }
    #[cfg(feature = "executable-plugins")]
    {
        PLUGIN_HOST
            .lock()
            .map_err(|_| AtlasError::LockPoisoned)?
            .install_js(&manifest_toml, &source, &ui_json)
            .map(PluginEntry::from)
            .map_err(|error| AtlasError::PluginError(error.to_string()))
    }
}

pub fn list_plugins() -> Result<Vec<PluginEntry>, AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        Ok(Vec::new())
    }
    #[cfg(feature = "executable-plugins")]
    {
        Ok(PLUGIN_HOST
            .lock()
            .map_err(|_| AtlasError::LockPoisoned)?
            .list()
            .into_iter()
            .map(PluginEntry::from)
            .collect())
    }
}

pub fn uninstall_plugin(id: String) -> Result<bool, AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = id;
        Ok(false)
    }
    #[cfg(feature = "executable-plugins")]
    {
        Ok(PLUGIN_HOST
            .lock()
            .map_err(|_| AtlasError::LockPoisoned)?
            .uninstall(&id))
    }
}

pub fn dispatch_plugin_event(id: String, event_json: String) -> Result<String, AtlasError> {
    #[cfg(not(feature = "executable-plugins"))]
    {
        let _ = (id, event_json);
        Err(AtlasError::PluginError(
            "Executable plugins are unavailable in this distribution".to_string(),
        ))
    }
    #[cfg(feature = "executable-plugins")]
    {
        PLUGIN_HOST
            .lock()
            .map_err(|_| AtlasError::LockPoisoned)?
            .dispatch_event(&id, &event_json)
            .map_err(|error| AtlasError::PluginError(error.to_string()))
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

#[cfg(test)]
mod tests {
    use super::*;

    static TEST_LOCK: Lazy<Mutex<()>> = Lazy::new(|| Mutex::new(()));

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
}

// MARK: - AI center

static AI_STORE: Lazy<Mutex<Option<atlas_ai::AiStore>>> = Lazy::new(|| Mutex::new(None));
static AI_REQUESTS: Lazy<Mutex<std::collections::HashMap<u64, tokio_util::sync::CancellationToken>>> =
    Lazy::new(|| Mutex::new(std::collections::HashMap::new()));
static AI_REQUEST_COUNTER: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);

pub struct AiProviderConfig {
    pub id: String,
    pub name: String,
    pub base_url: String,
    pub model: String,
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
        Self { id: p.id, name: p.name, base_url: p.base_url, model: p.model }
    }
}

impl From<AiProviderConfig> for atlas_ai::ProviderConfig {
    fn from(p: AiProviderConfig) -> Self {
        Self { id: p.id, name: p.name, base_url: p.base_url, model: p.model, extra_headers: vec![] }
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
        Self { id: s.id, title: s.title, created_at_ms: s.created_at_ms, message_count: s.message_count }
    }
}

impl From<atlas_ai::PromptPreset> for AiPromptPreset {
    fn from(p: atlas_ai::PromptPreset) -> Self {
        Self { id: p.id, name: p.name, system_prompt: p.system_prompt }
    }
}

impl From<AiPromptPreset> for atlas_ai::PromptPreset {
    fn from(p: AiPromptPreset) -> Self {
        Self { id: p.id, name: p.name, system_prompt: p.system_prompt }
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
        let _ = AI_REQUESTS.lock().map(|mut map| map.remove(&self.request_id));
        self.delegate.on_done(self.request_id);
    }
    fn on_error(&self, message: String) {
        let _ = AI_REQUESTS.lock().map(|mut map| map.remove(&self.request_id));
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
    };

    let request_id = AI_REQUEST_COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let cancel = tokio_util::sync::CancellationToken::new();
    AI_REQUESTS
        .lock()
        .map_err(|_| AtlasError::LockPoisoned)?
        .insert(request_id, cancel.clone());

    let sink = std::sync::Arc::new(DelegateSink { request_id, delegate });
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

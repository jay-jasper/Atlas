//! Atlas FFI Crate
//!
//! This crate provides a Foreign Function Interface (FFI) for the Atlas core functionality,
//! allowing it to be used from other languages via UniFFI.

use std::sync::{Arc, Mutex};
use once_cell::sync::Lazy;
use tokio::runtime::Runtime;
use tokio::task::JoinHandle;
use atlas_core::AtlasCore;
use thiserror::Error;

uniffi::include_scaffolding!("atlas");

/// Global instance of the Atlas core to preserve state across FFI calls.
static CORE: Lazy<Mutex<AtlasCore>> = Lazy::new(|| Mutex::new(AtlasCore::new()));

/// Control the monitoring background task.
static MONITOR_HANDLE: Lazy<Mutex<Option<JoinHandle<()>>>> = Lazy::new(|| Mutex::new(None));

/// Global Tokio runtime for background tasks.
static RUNTIME: Lazy<Runtime> = Lazy::new(|| Runtime::new().expect("Failed to create Tokio runtime"));

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
}

/// Represents the state of a feature module for FFI.
pub enum FeatureStatus {
    Enabled,
    Disabled,
}

/// A record representing a feature and its current status for FFI.
pub struct FeatureEntry {
    pub name: String,
    pub status: FeatureStatus,
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
            cpu_cores: s.cpu_cores.into_iter().map(|c| CpuCoreSnapshot {
                name: c.name,
                usage: c.usage,
                frequency_mhz: c.frequency_mhz,
            }).collect(),
            mem_free_bytes: s.mem_free_bytes,
            mem_available_bytes: s.mem_available_bytes,
            swap_used_bytes: s.swap_used_bytes,
            swap_total_bytes: s.swap_total_bytes,
            top_cpu_processes: s.top_cpu_processes.into_iter().map(|p| ProcessSnapshot {
                pid: p.pid,
                name: p.name,
                cpu_usage: p.cpu_usage,
                mem_bytes: p.mem_bytes,
            }).collect(),
            top_mem_processes: s.top_mem_processes.into_iter().map(|p| ProcessSnapshot {
                pid: p.pid,
                name: p.name,
                cpu_usage: p.cpu_usage,
                mem_bytes: p.mem_bytes,
            }).collect(),
            network_interfaces: s.network_interfaces.into_iter().map(|n| NetworkInterfaceSnapshot {
                name: n.name,
                upload_bps: n.upload_bps,
                download_bps: n.download_bps,
            }).collect(),
            disks: s.disks.into_iter().map(|d| DiskSnapshot {
                name: d.name,
                mount_point: d.mount_point,
                total_bytes: d.total_bytes,
                used_bytes: d.used_bytes,
                available_bytes: d.available_bytes,
            }).collect(),
            battery: s.battery.map(|b| BatterySnapshot {
                charge_percent: b.charge_percent,
                is_charging: b.is_charging,
                time_to_empty_secs: b.time_to_empty_secs,
                time_to_full_secs: b.time_to_full_secs,
                health_percent: b.health_percent,
                cycle_count: b.cycle_count,
            }),
            temperatures: s.temperatures.into_iter().map(|t| TemperatureSnapshot {
                label: t.label,
                celsius: t.celsius,
            }).collect(),
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
    Ok(core.feature_manager_mut()
        .toggle_feature(&name, enabled))
}

/// Returns a list of all available features and their status.
pub fn list_features() -> Result<Vec<FeatureEntry>, AtlasError> {
    // Important Issue 3: release the lock before allocation by binding raw first.
    let raw = CORE.lock().map_err(|_| AtlasError::LockPoisoned)?.feature_manager().list_features();
    Ok(raw.into_iter()
        .map(|(name, status)| FeatureEntry {
            name,
            status: status.into(),
        })
        .collect())
}

/// Starts real-time system monitoring.
///
/// This spawns a background task that collects system metrics every second
/// and pushes them to the provided callback. If monitoring is already active,
/// the existing task is stopped before starting a new one.
pub fn start_monitoring(callback: Box<dyn SystemMonitorCallback>) -> Result<(), AtlasError> {
    // Stop existing task if any, then release the lock before spawning (Important
    // Issue 4): holding the MutexGuard across RUNTIME.spawn() is unnecessary and
    // could deadlock if anything on the runtime thread also tries to acquire this
    // lock.
    {
        let mut handle_lock = MONITOR_HANDLE.lock().map_err(|_| AtlasError::LockPoisoned)?;
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
            }).await.ok();
            tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
        }
    });

    MONITOR_HANDLE.lock().map_err(|_| AtlasError::LockPoisoned)?.replace(handle);
    Ok(())
}

/// Stops real-time system monitoring.
pub fn stop_monitoring() -> Result<(), AtlasError> {
    let mut handle_lock = MONITOR_HANDLE.lock().map_err(|_| AtlasError::LockPoisoned)?;
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
    // Critical Issue 1: previously the code unwrapped the outer Result with `?`,
    // then called `.map(|info| Ok(...)).transpose()` — redundantly wrapping an
    // already-unwrapped Option value back into Ok before transposing. The correct
    // approach maps over the outer Result and the inner Option directly.
    atlas_core::monitor::port_master::find_process_by_port(port)
        .map_err(|e| AtlasError::ProcessError(e.to_string()))
        .map(|opt| opt.map(|info| PortProcessInfo {
            port: info.port,
            pid: info.pid,
            process_name: info.process_name,
        }))
}

/// Kills a process by its PID.
pub fn kill_port_process(pid: u32) -> Result<bool, AtlasError> {
    Ok(atlas_core::monitor::port_master::kill_process(pid))
}

/// Captures the full screen and returns PNG bytes.
///
/// Currently, this only supports the primary monitor.
pub fn capture_full_screen() -> Result<Vec<u8>, AtlasError> {
    atlas_core::capture::engine::CaptureEngine::capture_full_screen()
        .map_err(|e| AtlasError::CaptureError(e.to_string()))
}

/// Captures a specific region of the screen and returns PNG bytes.
///
/// Currently, this only supports the primary monitor.
pub fn capture_region(x: i32, y: i32, width: u32, height: u32) -> Result<Vec<u8>, AtlasError> {
    atlas_core::capture::engine::CaptureEngine::capture_region(x, y, width, height)
        .map_err(|e| AtlasError::CaptureError(e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_core_status() {
        let status = get_core_status().unwrap();
        assert!(status.contains("Atlas Core v"));
        assert!(status.contains("is running"));
    }

    #[test]
    fn test_feature_management() {
        let features = list_features().unwrap();
        let names: Vec<_> = features.iter().map(|f| f.name.as_str()).collect();
        assert_eq!(
            names,
            ["automation", "monitoring", "screenshot", "tokenbar", "window-manager"]
        );

        assert!(features.iter().any(|f| f.name == "automation"));
        assert!(features.iter().any(|f| f.name == "monitoring"));
        assert!(features.iter().any(|f| f.name == "screenshot"));
        assert!(features.iter().any(|f| f.name == "tokenbar"));
        assert!(features.iter().any(|f| f.name == "window-manager"));

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
        // In CI, these will likely return error in headless environment, 
        // but we want to ensure they are callable and return Result.
        let _ = capture_full_screen();
        let _ = capture_region(0, 0, 100, 100);
    }
}

use serde::{Deserialize, Serialize};

/// A snapshot of system performance metrics at a specific point in time.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SystemSnapshot {
    /// Total CPU usage as a percentage (0.0 to 100.0).
    pub cpu_usage: f32,
    /// Total system memory used, in bytes.
    pub mem_used_bytes: u64,
    /// Total system memory available, in bytes.
    pub mem_total_bytes: u64,
    /// Network upload rate, in bytes per second.
    pub net_upload_bps: u64,
    /// Network download rate, in bytes per second.
    pub net_download_bps: u64,
}

/// Information about a process associated with a specific network port.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PortProcessInfo {
    /// The network port number.
    pub port: u16,
    /// The process ID (PID) of the owner process.
    pub pid: u32,
    /// The name of the process.
    pub process_name: String,
}

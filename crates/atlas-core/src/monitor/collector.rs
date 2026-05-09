use crate::monitor::models::SystemSnapshot;
use sysinfo::{Networks, System};

/// Collects system performance metrics.
pub struct Collector {
    sys: System,
    networks: Networks,
    last_upload: u64,
    last_download: u64,
}

impl Collector {
    /// Creates a new `Collector` instance.
    pub fn new() -> Self {
        let mut sys = System::new();
        // Initial refresh to allow CPU usage calculation on first snapshot
        sys.refresh_cpu();

        let mut networks = Networks::new_with_refreshed_list();
        networks.refresh();

        let mut last_upload = 0;
        let mut last_download = 0;
        for (_, data) in &networks {
            last_upload += data.transmitted();
            last_download += data.received();
        }

        Self {
            sys,
            networks,
            last_upload,
            last_download,
        }
    }

    /// Takes a snapshot of current system metrics.
    pub fn take_snapshot(&mut self) -> SystemSnapshot {
        self.sys.refresh_cpu();
        self.sys.refresh_memory();
        self.networks.refresh();

        let cpu_usage = self.sys.global_cpu_info().cpu_usage();
        let mem_used_bytes = self.sys.used_memory();
        let mem_total_bytes = self.sys.total_memory();

        let mut current_upload = 0;
        let mut current_download = 0;
        for (_, data) in &self.networks {
            current_upload += data.transmitted();
            current_download += data.received();
        }

        let net_upload_bps = current_upload.saturating_sub(self.last_upload);
        let net_download_bps = current_download.saturating_sub(self.last_download);

        self.last_upload = current_upload;
        self.last_download = current_download;

        SystemSnapshot {
            cpu_usage,
            mem_used_bytes,
            mem_total_bytes,
            net_upload_bps,
            net_download_bps,
            cpu_cores: vec![],
            mem_free_bytes: 0,
            mem_available_bytes: 0,
            swap_used_bytes: 0,
            swap_total_bytes: 0,
            top_cpu_processes: vec![],
            top_mem_processes: vec![],
            network_interfaces: vec![],
            disks: vec![],
            battery: None,
            temperatures: vec![],
        }
    }
}

impl Default for Collector {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_take_snapshot() {
        let mut collector = Collector::new();
        // First snapshot might have 0 CPU usage because it needs two refreshes with delay
        let _ = collector.take_snapshot();

        // Wait a bit or just take another one (sysinfo 0.30 usually works better with a small delay)
        // But for unit test we just want to see if it doesn't panic and returns memory.
        let snapshot = collector.take_snapshot();

        assert!(snapshot.mem_total_bytes > 0);
        println!("Snapshot: {:?}", snapshot);
    }

    #[test]
    fn test_default() {
        let mut collector = Collector::default();
        let snapshot = collector.take_snapshot();
        assert!(snapshot.mem_total_bytes > 0);
    }
}

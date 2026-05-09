use std::collections::HashMap;

use sysinfo::{Networks, System};

use crate::monitor::models::{
    CpuCoreSnapshot, NetworkInterfaceSnapshot, ProcessSnapshot, SystemSnapshot,
};

pub struct Collector {
    sys: System,
    networks: Networks,
    last_iface_upload: HashMap<String, u64>,
    last_iface_download: HashMap<String, u64>,
    tick: u64,
    pub cached_disks: Vec<crate::monitor::models::DiskSnapshot>,
    pub cached_battery: Option<crate::monitor::models::BatterySnapshot>,
    pub cached_temps: Vec<crate::monitor::models::TemperatureSnapshot>,
}

impl Collector {
    pub fn new() -> Self {
        let mut sys = System::new();
        sys.refresh_cpu();
        sys.refresh_memory();

        let mut networks = Networks::new_with_refreshed_list();
        networks.refresh();

        let mut last_iface_upload = HashMap::new();
        let mut last_iface_download = HashMap::new();
        for (name, data) in &networks {
            last_iface_upload.insert(name.clone(), data.transmitted());
            last_iface_download.insert(name.clone(), data.received());
        }

        Self {
            sys,
            networks,
            last_iface_upload,
            last_iface_download,
            tick: 0,
            cached_disks: vec![],
            cached_battery: None,
            cached_temps: vec![],
        }
    }

    pub fn take_snapshot(&mut self) -> SystemSnapshot {
        self.sys.refresh_cpu();
        self.sys.refresh_memory();
        self.sys.refresh_processes();
        self.networks.refresh();

        if self.tick % 30 == 0 {
            self.cached_disks = crate::monitor::disk::get_disk_info();
            self.cached_battery = crate::monitor::battery::get_battery_info()
                .ok()
                .flatten();
            self.cached_temps = crate::monitor::sensors::get_temperatures();
        }
        self.tick += 1;

        let cpu_usage = self.sys.global_cpu_info().cpu_usage();

        let cpu_cores: Vec<CpuCoreSnapshot> = self
            .sys
            .cpus()
            .iter()
            .map(|cpu| CpuCoreSnapshot {
                name: cpu.name().to_string(),
                usage: cpu.cpu_usage(),
                frequency_mhz: cpu.frequency(),
            })
            .collect();

        let mem_used_bytes = self.sys.used_memory();
        let mem_total_bytes = self.sys.total_memory();
        let mem_free_bytes = self.sys.free_memory();
        let mem_available_bytes = self.sys.available_memory();
        let swap_used_bytes = self.sys.used_swap();
        let swap_total_bytes = self.sys.total_swap();

        let mut processes: Vec<_> = self.sys.processes().values().collect();
        processes.sort_by(|a, b| {
            b.cpu_usage()
                .partial_cmp(&a.cpu_usage())
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        let top_cpu_processes: Vec<ProcessSnapshot> = processes
            .iter()
            .take(5)
            .map(|p| ProcessSnapshot {
                pid: usize::from(p.pid()) as u32,
                name: p.name().to_string(),
                cpu_usage: p.cpu_usage(),
                mem_bytes: p.memory(),
            })
            .collect();

        processes.sort_by(|a, b| b.memory().cmp(&a.memory()));
        let top_mem_processes: Vec<ProcessSnapshot> = processes
            .iter()
            .take(5)
            .map(|p| ProcessSnapshot {
                pid: usize::from(p.pid()) as u32,
                name: p.name().to_string(),
                cpu_usage: p.cpu_usage(),
                mem_bytes: p.memory(),
            })
            .collect();

        let mut network_interfaces: Vec<NetworkInterfaceSnapshot> = vec![];
        let mut total_upload: u64 = 0;
        let mut total_download: u64 = 0;

        for (name, data) in &self.networks {
            let prev_up = self.last_iface_upload.get(name).copied().unwrap_or(0);
            let prev_dn = self.last_iface_download.get(name).copied().unwrap_or(0);
            let upload_bps = data.transmitted().saturating_sub(prev_up);
            let download_bps = data.received().saturating_sub(prev_dn);

            self.last_iface_upload.insert(name.clone(), data.transmitted());
            self.last_iface_download.insert(name.clone(), data.received());

            total_upload += upload_bps;
            total_download += download_bps;

            if upload_bps > 0 || download_bps > 0 || name.starts_with("en") {
                network_interfaces.push(NetworkInterfaceSnapshot {
                    name: name.clone(),
                    upload_bps,
                    download_bps,
                });
            }
        }

        SystemSnapshot {
            cpu_usage,
            cpu_cores,
            mem_used_bytes,
            mem_total_bytes,
            mem_free_bytes,
            mem_available_bytes,
            swap_used_bytes,
            swap_total_bytes,
            top_cpu_processes,
            top_mem_processes,
            net_upload_bps: total_upload,
            net_download_bps: total_download,
            network_interfaces,
            disks: self.cached_disks.clone(),
            battery: self.cached_battery.clone(),
            temperatures: self.cached_temps.clone(),
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
    fn test_snapshot_has_cpu_cores() {
        let mut c = Collector::new();
        let s = c.take_snapshot();
        assert!(!s.cpu_cores.is_empty(), "Should have at least one CPU core");
        assert!(s.cpu_cores[0].frequency_mhz > 0);
    }

    #[test]
    fn test_snapshot_memory_breakdown() {
        let mut c = Collector::new();
        let s = c.take_snapshot();
        assert!(s.mem_total_bytes > 0);
        assert!(s.mem_free_bytes <= s.mem_total_bytes);
    }

    #[test]
    fn test_snapshot_has_processes() {
        let mut c = Collector::new();
        let s = c.take_snapshot();
        assert!(!s.top_cpu_processes.is_empty(), "Should find running processes");
        assert!(s.top_cpu_processes.len() <= 5);
        assert!(s.top_mem_processes.len() <= 5);
    }

    #[test]
    fn test_snapshot_network_interfaces() {
        let mut c = Collector::new();
        let _ = c.take_snapshot();
        let s = c.take_snapshot();
        for iface in &s.network_interfaces {
            assert!(!iface.name.is_empty());
        }
    }
}

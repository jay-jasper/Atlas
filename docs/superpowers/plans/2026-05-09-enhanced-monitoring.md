# Enhanced System Monitoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 参考 iStat Menus 7 与 Stats，将监控模块从"基础全局指标"升级为"多维度富信息采集"，覆盖 CPU 每核详情、内存分类（空闲/交换）、进程排行、磁盘空间、电池状态、温度传感器、网络每接口流量，以及全新的 SwiftUI 富信息展示 UI。

**Architecture:** `atlas-core` 的 `Collector` 负责高频指标（CPU/内存/网络/进程，1s 刷新）；新增 `disk.rs`、`battery.rs`、`sensors.rs` 三个辅助模块提供低频数据（30s 缓存）；`SystemSnapshot` 扩展为全量超集；FFI 层新增对应 UDL dictionary 类型并更新转换逻辑；SwiftUI ContentView 重新设计为分区展示，参考 iStat/Stats 视觉风格（迷你核心柱状图、内存分段条、磁盘空间条、电池图标）。

**Tech Stack:** Rust, sysinfo 0.30, battery 0.7, anyhow, UniFFI 0.28, SwiftUI.

---

## 文件结构

```
crates/atlas-core/src/monitor/
  models.rs          ← 扩展 SystemSnapshot + 6 个新数据结构
  collector.rs       ← 扩展 Collector：每核 CPU、内存分类、进程排行、每接口网络
  disk.rs            ← 新建：磁盘卷信息
  battery.rs         ← 新建：电池状态（battery crate）
  sensors.rs         ← 新建：温度传感器（sysinfo Components）
  mod.rs             ← 导出新模块

crates/atlas-ffi/src/
  atlas.udl          ← 新增 6 个 dictionary 类型，更新 SystemSnapshot
  lib.rs             ← 更新 SystemSnapshot 转换逻辑，新增 FFI 结构体

platforms/macos/Atlas/
  ContentView.swift  ← 重新设计监控 UI
```

---

### Task 1: 扩展数据模型

**Files:**
- Modify: `crates/atlas-core/src/monitor/models.rs`

- [ ] **Step 1: 在 models.rs 中添加 6 个新结构体，并扩展 SystemSnapshot**

```rust
// crates/atlas-core/src/monitor/models.rs
use serde::{Deserialize, Serialize};

/// 每个 CPU 核心的快照数据。
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct CpuCoreSnapshot {
    /// 核心名称，如 "cpu0"。
    pub name: String,
    /// 使用率，0.0 ~ 100.0。
    pub usage: f32,
    /// 当前频率（MHz）。
    pub frequency_mhz: u64,
}

/// 进程快照，用于进程排行。
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ProcessSnapshot {
    pub pid: u32,
    pub name: String,
    /// CPU 使用率，0.0 ~ 100.0。
    pub cpu_usage: f32,
    /// 内存占用（字节）。
    pub mem_bytes: u64,
}

/// 单个网络接口的流量快照。
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct NetworkInterfaceSnapshot {
    pub name: String,
    pub upload_bps: u64,
    pub download_bps: u64,
}

/// 磁盘卷空间快照。
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DiskSnapshot {
    /// 卷名（如 "Macintosh HD"）。
    pub name: String,
    /// 挂载点（如 "/"）。
    pub mount_point: String,
    pub total_bytes: u64,
    pub used_bytes: u64,
    pub available_bytes: u64,
}

/// 电池状态快照。
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct BatterySnapshot {
    /// 当前电量百分比，0.0 ~ 100.0。
    pub charge_percent: f32,
    pub is_charging: bool,
    /// 距离耗尽的秒数（放电时有值）。
    pub time_to_empty_secs: Option<i64>,
    /// 距离充满的秒数（充电时有值）。
    pub time_to_full_secs: Option<i64>,
    /// 电池健康度，0.0 ~ 100.0。
    pub health_percent: f32,
    /// 充放电循环次数。
    pub cycle_count: Option<u32>,
}

/// 温度传感器读数。
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct TemperatureSnapshot {
    /// 传感器标签，如 "CPU Core 0"。
    pub label: String,
    /// 温度（摄氏度）。
    pub celsius: f32,
}

/// 全量系统快照，包含所有监控维度。
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SystemSnapshot {
    // ── 基础指标（原有）──
    pub cpu_usage: f32,
    pub mem_used_bytes: u64,
    pub mem_total_bytes: u64,
    pub net_upload_bps: u64,
    pub net_download_bps: u64,

    // ── CPU 每核详情 ──
    pub cpu_cores: Vec<CpuCoreSnapshot>,

    // ── 内存分类 ──
    pub mem_free_bytes: u64,
    pub mem_available_bytes: u64,
    pub swap_used_bytes: u64,
    pub swap_total_bytes: u64,

    // ── 进程排行（各取 Top 5）──
    pub top_cpu_processes: Vec<ProcessSnapshot>,
    pub top_mem_processes: Vec<ProcessSnapshot>,

    // ── 网络每接口 ──
    pub network_interfaces: Vec<NetworkInterfaceSnapshot>,

    // ── 磁盘空间（低频缓存）──
    pub disks: Vec<DiskSnapshot>,

    // ── 电池（低频缓存，台式机为 None）──
    pub battery: Option<BatterySnapshot>,

    // ── 温度传感器（低频缓存）──
    pub temperatures: Vec<TemperatureSnapshot>,
}

/// 监听端口的进程信息（原有）。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PortProcessInfo {
    pub port: u16,
    pub pid: u32,
    pub process_name: String,
}
```

- [ ] **Step 2: 运行编译验证模型无误**

Run: `cargo build -p atlas-core`
Expected: Compiles successfully (no new tests needed for pure data structs)

- [ ] **Step 3: Commit**

```bash
git add crates/atlas-core/src/monitor/models.rs
git commit -m "feat(monitor): extend SystemSnapshot with rich metrics models"
```

---

### Task 2: Collector — 每核 CPU 详情

**Files:**
- Modify: `crates/atlas-core/src/monitor/collector.rs`

- [ ] **Step 1: 在 `take_snapshot` 中添加每核 CPU 采集**

将 collector.rs 替换为以下内容（保留原有字段，新增 `cpu_cores`）：

```rust
// crates/atlas-core/src/monitor/collector.rs
use std::collections::HashMap;

use sysinfo::{Networks, System};

use crate::monitor::models::{
    CpuCoreSnapshot, NetworkInterfaceSnapshot, ProcessSnapshot, SystemSnapshot,
};

pub struct Collector {
    sys: System,
    networks: Networks,
    // 每接口上次的流量累计值（用于计算增量 bps）
    last_iface_upload: HashMap<String, u64>,
    last_iface_download: HashMap<String, u64>,
    // 慢刷新计数器（每 30 tick 刷新磁盘/电池/温度）
    tick: u64,
    // 慢刷新缓存
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
        // ── 高频刷新 ──
        self.sys.refresh_cpu();
        self.sys.refresh_memory();
        self.sys.refresh_processes();
        self.networks.refresh();

        // ── 低频刷新（每 30 秒）──
        if self.tick % 30 == 0 {
            self.cached_disks = crate::monitor::disk::get_disk_info();
            self.cached_battery = crate::monitor::battery::get_battery_info()
                .ok()
                .flatten();
            self.cached_temps = crate::monitor::sensors::get_temperatures();
        }
        self.tick += 1;

        // ── CPU 全局 ──
        let cpu_usage = self.sys.global_cpu_info().cpu_usage();

        // ── CPU 每核 ──
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

        // ── 内存 ──
        let mem_used_bytes = self.sys.used_memory();
        let mem_total_bytes = self.sys.total_memory();
        let mem_free_bytes = self.sys.free_memory();
        let mem_available_bytes = self.sys.available_memory();
        let swap_used_bytes = self.sys.used_swap();
        let swap_total_bytes = self.sys.total_swap();

        // ── 进程排行（Top 5）──
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

        // ── 网络每接口 ──
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

            // 过滤掉流量为 0 的回环等接口（可按需调整）
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
        assert!(s.swap_total_bytes >= 0);
        // free + used ≤ total (within rounding)
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
        let _ = c.take_snapshot(); // baseline
        let s = c.take_snapshot();
        // At minimum we should have at least one interface (even if bps = 0)
        // The test just verifies no panic and correct types
        for iface in &s.network_interfaces {
            assert!(!iface.name.is_empty());
        }
    }
}
```

- [ ] **Step 2: 运行测试**

Run: `cargo test -p atlas-core monitor::collector`
Expected: 4 tests pass (snapshot_has_cpu_cores, memory_breakdown, has_processes, network_interfaces)

- [ ] **Step 3: Commit**

```bash
git add crates/atlas-core/src/monitor/collector.rs
git commit -m "feat(monitor): add per-core CPU, memory breakdown, top processes, per-interface network"
```

---

### Task 3: 磁盘信息模块

**Files:**
- Create: `crates/atlas-core/src/monitor/disk.rs`
- Modify: `crates/atlas-core/src/monitor/mod.rs`

- [ ] **Step 1: 创建 disk.rs**

```rust
// crates/atlas-core/src/monitor/disk.rs
use sysinfo::Disks;

use crate::monitor::models::DiskSnapshot;

/// 返回所有已挂载卷的空间信息。
pub fn get_disk_info() -> Vec<DiskSnapshot> {
    Disks::new_with_refreshed_list()
        .iter()
        .map(|disk| {
            let total = disk.total_space();
            let available = disk.available_space();
            let used = total.saturating_sub(available);
            DiskSnapshot {
                name: disk.name().to_string_lossy().to_string(),
                mount_point: disk.mount_point().to_string_lossy().to_string(),
                total_bytes: total,
                used_bytes: used,
                available_bytes: available,
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_disk_info_non_empty() {
        let disks = get_disk_info();
        assert!(!disks.is_empty(), "Should find at least one disk volume");
    }

    #[test]
    fn test_disk_used_plus_available_equals_total() {
        for disk in get_disk_info() {
            assert_eq!(
                disk.used_bytes + disk.available_bytes,
                disk.total_bytes,
                "used + available should equal total for {}",
                disk.name
            );
        }
    }
}
```

- [ ] **Step 2: 在 mod.rs 中导出 disk 模块**

```rust
// crates/atlas-core/src/monitor/mod.rs
pub mod collector;
pub mod disk;
pub mod models;
pub mod port_master;
pub mod battery;
pub mod sensors;
```

（注：battery 和 sensors 模块在后续任务中创建，这里先声明以让编译器知道）

实际上先只添加 disk，其余两行等 Task 4/5 完成后再加：

```rust
// crates/atlas-core/src/monitor/mod.rs
pub mod collector;
pub mod disk;
pub mod models;
pub mod port_master;
```

- [ ] **Step 3: 运行测试**

Run: `cargo test -p atlas-core monitor::disk`
Expected: 2 tests pass

- [ ] **Step 4: Commit**

```bash
git add crates/atlas-core/src/monitor/disk.rs crates/atlas-core/src/monitor/mod.rs
git commit -m "feat(monitor): add disk volume info module"
```

---

### Task 4: 电池状态模块

**Files:**
- Modify: `crates/atlas-core/Cargo.toml`
- Create: `crates/atlas-core/src/monitor/battery.rs`
- Modify: `crates/atlas-core/src/monitor/mod.rs`

- [ ] **Step 1: 添加 battery crate 依赖**

```toml
# crates/atlas-core/Cargo.toml [dependencies] 中添加：
battery = "0.7"
```

- [ ] **Step 2: 创建 battery.rs**

```rust
// crates/atlas-core/src/monitor/battery.rs
use anyhow::Result;
use battery::{
    units::{ratio::percent, time::second},
    Manager, State,
};

use crate::monitor::models::BatterySnapshot;

/// 返回第一块电池的状态。台式机或无法读取时返回 `Ok(None)`。
pub fn get_battery_info() -> Result<Option<BatterySnapshot>> {
    let manager = Manager::new()?;
    let mut batteries = manager.batteries()?;

    let Some(result) = batteries.next() else {
        return Ok(None);
    };
    let battery = result?;

    let charge_percent = battery.state_of_charge().get::<percent>();
    let is_charging = matches!(battery.state(), State::Charging | State::Full);
    let time_to_empty_secs = battery
        .time_to_empty()
        .map(|t| t.get::<second>() as i64);
    let time_to_full_secs = battery
        .time_to_full()
        .map(|t| t.get::<second>() as i64);
    let health_percent = battery.state_of_health().get::<percent>();
    let cycle_count = battery.cycle_count();

    Ok(Some(BatterySnapshot {
        charge_percent,
        is_charging,
        time_to_empty_secs,
        time_to_full_secs,
        health_percent,
        cycle_count,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_battery_info_does_not_panic() {
        // 台式机会返回 Ok(None)，MacBook 会返回 Ok(Some(...))
        let result = get_battery_info();
        assert!(result.is_ok(), "battery::get_battery_info() should not error");
    }

    #[test]
    fn test_battery_charge_in_range() {
        if let Ok(Some(b)) = get_battery_info() {
            assert!(
                b.charge_percent >= 0.0 && b.charge_percent <= 100.0,
                "charge_percent out of range: {}",
                b.charge_percent
            );
            assert!(
                b.health_percent >= 0.0 && b.health_percent <= 100.0,
                "health_percent out of range: {}",
                b.health_percent
            );
        }
    }
}
```

- [ ] **Step 3: 在 mod.rs 中导出 battery**

```rust
// crates/atlas-core/src/monitor/mod.rs
pub mod battery;
pub mod collector;
pub mod disk;
pub mod models;
pub mod port_master;
```

- [ ] **Step 4: 运行测试**

Run: `cargo test -p atlas-core monitor::battery`
Expected: 2 tests pass（无电池设备时 battery_charge_in_range 直接 pass）

- [ ] **Step 5: Commit**

```bash
git add crates/atlas-core/Cargo.toml crates/atlas-core/src/monitor/battery.rs crates/atlas-core/src/monitor/mod.rs
git commit -m "feat(monitor): add battery status module"
```

---

### Task 5: 温度传感器模块

**Files:**
- Create: `crates/atlas-core/src/monitor/sensors.rs`
- Modify: `crates/atlas-core/src/monitor/mod.rs`

- [ ] **Step 1: 创建 sensors.rs**

```rust
// crates/atlas-core/src/monitor/sensors.rs
use sysinfo::Components;

use crate::monitor::models::TemperatureSnapshot;

/// 返回所有可用温度传感器的读数。
/// 注意：macOS 受系统权限限制，可能返回空列表或仅部分传感器。
pub fn get_temperatures() -> Vec<TemperatureSnapshot> {
    Components::new_with_refreshed_list()
        .iter()
        .map(|c| TemperatureSnapshot {
            label: c.label().to_string(),
            celsius: c.temperature(),
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_temperatures_does_not_panic() {
        // macOS 可能返回空列表，不视为错误
        let temps = get_temperatures();
        for t in &temps {
            assert!(!t.label.is_empty());
            // 合理温度范围：0°C ~ 150°C
            assert!(t.celsius >= 0.0 && t.celsius < 150.0,
                "Suspicious temperature for {}: {}°C", t.label, t.celsius);
        }
    }
}
```

- [ ] **Step 2: 在 mod.rs 中导出 sensors**

```rust
// crates/atlas-core/src/monitor/mod.rs
pub mod battery;
pub mod collector;
pub mod disk;
pub mod models;
pub mod port_master;
pub mod sensors;
```

- [ ] **Step 3: 运行全量测试**

Run: `cargo test -p atlas-core`
Expected: 所有测试通过（原有 11 个 + 新增约 9 个）

- [ ] **Step 4: Commit**

```bash
git add crates/atlas-core/src/monitor/sensors.rs crates/atlas-core/src/monitor/mod.rs
git commit -m "feat(monitor): add temperature sensors module"
```

---

### Task 6: 更新 FFI 桥接层

**Files:**
- Modify: `crates/atlas-ffi/src/atlas.udl`
- Modify: `crates/atlas-ffi/src/lib.rs`

- [ ] **Step 1: 更新 atlas.udl，新增 6 个 dictionary 类型并扩展 SystemSnapshot**

将 `atlas.udl` 中的 `SystemSnapshot` 及相关内容替换为：

```udl
dictionary CpuCoreSnapshot {
    string name;
    float usage;
    u64 frequency_mhz;
};

dictionary ProcessSnapshot {
    u32 pid;
    string name;
    float cpu_usage;
    u64 mem_bytes;
};

dictionary NetworkInterfaceSnapshot {
    string name;
    u64 upload_bps;
    u64 download_bps;
};

dictionary DiskSnapshot {
    string name;
    string mount_point;
    u64 total_bytes;
    u64 used_bytes;
    u64 available_bytes;
};

dictionary BatterySnapshot {
    float charge_percent;
    boolean is_charging;
    i64? time_to_empty_secs;
    i64? time_to_full_secs;
    float health_percent;
    u32? cycle_count;
};

dictionary TemperatureSnapshot {
    string label;
    float celsius;
};

dictionary SystemSnapshot {
    float cpu_usage;
    u64 mem_used_bytes;
    u64 mem_total_bytes;
    u64 net_upload_bps;
    u64 net_download_bps;

    sequence<CpuCoreSnapshot> cpu_cores;
    u64 mem_free_bytes;
    u64 mem_available_bytes;
    u64 swap_used_bytes;
    u64 swap_total_bytes;
    sequence<ProcessSnapshot> top_cpu_processes;
    sequence<ProcessSnapshot> top_mem_processes;
    sequence<NetworkInterfaceSnapshot> network_interfaces;
    sequence<DiskSnapshot> disks;
    BatterySnapshot? battery;
    sequence<TemperatureSnapshot> temperatures;
};
```

其余 UDL 内容（FeatureEntry、PortProcessInfo、callback interface、namespace）保持不变。

- [ ] **Step 2: 在 lib.rs 中新增 6 个 FFI 结构体，更新 SystemSnapshot 及其转换逻辑**

在 lib.rs 的现有 `SystemSnapshot` 结构体定义处（及其 `From` 实现）进行以下更新：

```rust
// crates/atlas-ffi/src/lib.rs
// （在 uniffi::include_scaffolding!("atlas"); 之后，现有代码之前添加以下结构体）

// ── 新增 FFI 结构体 ──

pub struct CpuCoreSnapshot {
    pub name: String,
    pub usage: f32,
    pub frequency_mhz: u64,
}

pub struct ProcessSnapshot {
    pub pid: u32,
    pub name: String,
    pub cpu_usage: f32,
    pub mem_bytes: u64,
}

pub struct NetworkInterfaceSnapshot {
    pub name: String,
    pub upload_bps: u64,
    pub download_bps: u64,
}

pub struct DiskSnapshot {
    pub name: String,
    pub mount_point: String,
    pub total_bytes: u64,
    pub used_bytes: u64,
    pub available_bytes: u64,
}

pub struct BatterySnapshot {
    pub charge_percent: f32,
    pub is_charging: bool,
    pub time_to_empty_secs: Option<i64>,
    pub time_to_full_secs: Option<i64>,
    pub health_percent: f32,
    pub cycle_count: Option<u32>,
}

pub struct TemperatureSnapshot {
    pub label: String,
    pub celsius: f32,
}

// ── 扩展 SystemSnapshot（替换原有定义）──

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

// ── 更新 From 转换（替换原有的 From<core::SystemSnapshot>）──

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
```

- [ ] **Step 3: 构建验证**

Run: `cargo build -p atlas-ffi`
Expected: Compiles successfully

- [ ] **Step 4: 运行 FFI 测试**

Run: `cargo test -p atlas-ffi`
Expected: All tests pass (test_get_core_status, test_feature_management, test_port_lookup, test_capture_functions_exist)

- [ ] **Step 5: Commit**

```bash
git add crates/atlas-ffi/src/atlas.udl crates/atlas-ffi/src/lib.rs
git commit -m "feat(ffi): extend UDL and FFI bridge with rich monitoring types"
```

---

### Task 7: SwiftUI 富信息监控 UI

**Files:**
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [ ] **Step 1: 更新 ContentView.swift 的数据模型和 Mock Bridge**

将 `SystemSnapshot` struct 和 `AtlasBridge` 的 mock 数据更新为包含新字段：

```swift
// platforms/macos/Atlas/ContentView.swift

import SwiftUI

// ── 数据模型（对应 FFI 中的结构体）──

struct CpuCoreSnapshot {
    let name: String
    let usage: Float
    let frequencyMhz: UInt64
}

struct ProcessSnapshot {
    let pid: UInt32
    let name: String
    let cpuUsage: Float
    let memBytes: UInt64
}

struct NetworkInterfaceSnapshot {
    let name: String
    let uploadBps: UInt64
    let downloadBps: UInt64
}

struct DiskSnapshot {
    let name: String
    let mountPoint: String
    let totalBytes: UInt64
    let usedBytes: UInt64
    let availableBytes: UInt64
}

struct BatterySnapshot {
    let chargePercent: Float
    let isCharging: Bool
    let timeToEmptySecs: Int64?
    let timeToFullSecs: Int64?
    let healthPercent: Float
    let cycleCount: UInt32?
}

struct TemperatureSnapshot {
    let label: String
    let celsius: Float
}

struct SystemSnapshot {
    let cpuUsage: Float
    let memUsedBytes: UInt64
    let memTotalBytes: UInt64
    let netUploadBps: UInt64
    let netDownloadBps: UInt64

    let cpuCores: [CpuCoreSnapshot]
    let memFreeBytes: UInt64
    let memAvailableBytes: UInt64
    let swapUsedBytes: UInt64
    let swapTotalBytes: UInt64
    let topCpuProcesses: [ProcessSnapshot]
    let topMemProcesses: [ProcessSnapshot]
    let networkInterfaces: [NetworkInterfaceSnapshot]
    let disks: [DiskSnapshot]
    let battery: BatterySnapshot?
    let temperatures: [TemperatureSnapshot]
}

// ── Mock Bridge ──

class AtlasBridge {
    static var monitoringTimer: Timer?

    static func listFeatures() -> [String] {
        return ["Logging", "Auto-Updates", "Experimental Mode"]
    }

    static func toggleFeature(name: String, enabled: Bool) {
        print("Feature \(name) toggled to \(enabled)")
    }

    static func startMonitoring(callback: @escaping (SystemSnapshot) -> Void) {
        monitoringTimer?.invalidate()
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let coreCount = 10
            let cores = (0..<coreCount).map { i in
                CpuCoreSnapshot(
                    name: "cpu\(i)",
                    usage: Float.random(in: 5...95),
                    frequencyMhz: UInt64.random(in: 2400...3600)
                )
            }
            let processes = (0..<5).map { i in
                ProcessSnapshot(
                    pid: UInt32(1000 + i),
                    name: ["Xcode", "Safari", "Slack", "Terminal", "Finder"][i],
                    cpuUsage: Float.random(in: 0...40),
                    memBytes: UInt64.random(in: 50_000_000...500_000_000)
                )
            }
            let interfaces = [
                NetworkInterfaceSnapshot(name: "en0", uploadBps: UInt64.random(in: 0...500_000), downloadBps: UInt64.random(in: 0...2_000_000)),
                NetworkInterfaceSnapshot(name: "en1", uploadBps: 0, downloadBps: 0),
            ]
            let disks = [
                DiskSnapshot(name: "Macintosh HD", mountPoint: "/", totalBytes: 500_000_000_000, usedBytes: 250_000_000_000, availableBytes: 250_000_000_000),
                DiskSnapshot(name: "Data", mountPoint: "/System/Volumes/Data", totalBytes: 500_000_000_000, usedBytes: 300_000_000_000, availableBytes: 200_000_000_000),
            ]
            let battery = BatterySnapshot(
                chargePercent: 78.0,
                isCharging: false,
                timeToEmptySecs: 7200,
                timeToFullSecs: nil,
                healthPercent: 95.0,
                cycleCount: 143
            )
            let temps = [
                TemperatureSnapshot(label: "CPU Core 1", celsius: 55.0),
                TemperatureSnapshot(label: "CPU Core 2", celsius: 57.0),
                TemperatureSnapshot(label: "GPU", celsius: 48.0),
            ]

            callback(SystemSnapshot(
                cpuUsage: cores.map(\.usage).reduce(0, +) / Float(cores.count),
                memUsedBytes: 8_500_000_000,
                memTotalBytes: 16_000_000_000,
                netUploadBps: interfaces.map(\.uploadBps).reduce(0, +),
                netDownloadBps: interfaces.map(\.downloadBps).reduce(0, +),
                cpuCores: cores,
                memFreeBytes: 1_500_000_000,
                memAvailableBytes: 4_000_000_000,
                swapUsedBytes: 512_000_000,
                swapTotalBytes: 2_048_000_000,
                topCpuProcesses: processes.sorted { $0.cpuUsage > $1.cpuUsage },
                topMemProcesses: processes.sorted { $0.memBytes > $1.memBytes },
                networkInterfaces: interfaces,
                disks: disks,
                battery: battery,
                temperatures: temps
            ))
        }
    }

    static func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }

    static func killPortProcess(pid: UInt32) -> Bool {
        print("Killing process \(pid)")
        return true
    }

    static func captureRegion(x: Int32, y: Int32, width: UInt32, height: UInt32) -> Data? {
        print("Capturing region: x=\(x), y=\(y), width=\(width), height=\(height)")
        return Data()
    }

    static func captureFullScreen() -> Data? {
        return Data()
    }
}
```

- [ ] **Step 2: 重新设计 ContentView 的监控区块**

将 ContentView 的 body 中 "System Monitoring" 区块替换为：

```swift
struct ContentView: View {
    @State private var statusText: String = "Initializing..."
    @State private var features: [String] = []
    @State private var enabledFeatures: [String: Bool] = [:]

    // 监控数据
    @State private var snapshot: SystemSnapshot? = nil

    // Port Master
    @State private var portInput: String = ""
    @State private var portError: String = ""

    // Screenshot
    @State private var isShowingSelectionOverlay: Bool = false
    @State private var captureStatus: String = ""
    @State private var showCaptureStatus: Bool = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(statusText).font(.headline)

                    if showCaptureStatus {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text(captureStatus).font(.caption)
                        }
                        .padding(8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }

                    Divider()

                    // ── 截图 ──
                    Group {
                        Text("Screenshot").font(.subheadline).foregroundColor(.secondary)
                        Button(action: { isShowingSelectionOverlay = true }) {
                            HStack {
                                Image(systemName: "selection.pin.in.out")
                                Text("Select Area to Capture")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Divider()

                    // ── CPU ──
                    if let s = snapshot {
                        cpuSection(s)
                        Divider()
                        memorySection(s)
                        Divider()
                        networkSection(s)
                        Divider()
                        diskSection(s)
                        Divider()
                        if let bat = s.battery { batterySection(bat) ; Divider() }
                        if !s.temperatures.isEmpty { temperatureSection(s) ; Divider() }
                        processSection(s)
                        Divider()
                    } else {
                        ProgressView("Loading...").padding()
                        Divider()
                    }

                    // ── Port Master ──
                    Group {
                        Text("Port Master").font(.subheadline).foregroundColor(.secondary)
                        HStack {
                            TextField("PID", text: $portInput).textFieldStyle(RoundedBorderTextFieldStyle())
                            Button("Kill") {
                                guard let pid = UInt32(portInput) else {
                                    portError = "Invalid: \"\(portInput)\""
                                    return
                                }
                                portError = ""
                                if AtlasBridge.killPortProcess(pid: pid) { portInput = "" }
                            }
                            .disabled(portInput.isEmpty)
                        }
                        if !portError.isEmpty {
                            Text(portError).font(.caption).foregroundColor(.red)
                        }
                    }

                    Divider()

                    // ── Features ──
                    Text("Features").font(.subheadline).foregroundColor(.secondary)
                    ForEach(features, id: \.self) { f in
                        Toggle(f, isOn: Binding(
                            get: { enabledFeatures[f, default: false] },
                            set: { v in enabledFeatures[f] = v; AtlasBridge.toggleFeature(name: f, enabled: v) }
                        ))
                    }

                    Divider()

                    HStack {
                        Button("Settings") { NSApp.activate(ignoringOtherApps: true) }
                        Spacer()
                        Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
                    }
                }
                .padding()
            }

            if isShowingSelectionOverlay {
                SelectionOverlay { rect in
                    if let _ = AtlasBridge.captureRegion(
                        x: Int32(rect.minX), y: Int32(rect.minY),
                        width: UInt32(rect.width), height: UInt32(rect.height)
                    ) {
                        captureStatus = "Captured \(Int(rect.width))×\(Int(rect.height)) px"
                        showCaptureStatus = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showCaptureStatus = false }
                    }
                    isShowingSelectionOverlay = false
                }
            }
        }
        .frame(minWidth: 360, minHeight: 500)
        .onAppear {
            features = AtlasBridge.listFeatures()
            statusText = "Atlas is Ready"
            AtlasBridge.startMonitoring { s in
                DispatchQueue.main.async { self.snapshot = s }
            }
        }
        .onDisappear { AtlasBridge.stopMonitoring() }
    }

    // ── CPU 区块（全局 + 每核迷你柱状图）──
    @ViewBuilder
    private func cpuSection(_ s: SystemSnapshot) -> some View {
        Group {
            Text("CPU").font(.subheadline).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Total"); Spacer()
                    Text(String(format: "%.1f%%", s.cpuUsage))
                        .foregroundColor(s.cpuUsage > 80 ? .red : .primary)
                }
                ProgressView(value: s.cpuUsage, total: 100)
                    .accentColor(s.cpuUsage > 80 ? .red : .blue)

                // 每核迷你柱状图
                if !s.cpuCores.isEmpty {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(s.cpuCores.indices, id: \.self) { i in
                            let usage = CGFloat(s.cpuCores[i].usage) / 100.0
                            Rectangle()
                                .fill(coreColor(s.cpuCores[i].usage))
                                .frame(width: 10, height: max(2, 32 * usage))
                        }
                    }
                    .frame(height: 32)
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
    }

    // ── 内存区块（使用条 + 交换分区）──
    @ViewBuilder
    private func memorySection(_ s: SystemSnapshot) -> some View {
        Group {
            Text("Memory").font(.subheadline).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Used"); Spacer()
                    Text("\(fmt(s.memUsedBytes)) / \(fmt(s.memTotalBytes))")
                }
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        let used = CGFloat(s.memUsedBytes) / CGFloat(max(1, s.memTotalBytes))
                        Rectangle().fill(Color.blue).frame(width: geo.size.width * used)
                        Rectangle().fill(Color.blue.opacity(0.2)).frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 8)
                .cornerRadius(4)

                if s.swapTotalBytes > 0 {
                    HStack {
                        Text("Swap").foregroundColor(.secondary).font(.caption)
                        Spacer()
                        Text("\(fmt(s.swapUsedBytes)) / \(fmt(s.swapTotalBytes))")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
    }

    // ── 网络区块（总量 + 每接口）──
    @ViewBuilder
    private func networkSection(_ s: SystemSnapshot) -> some View {
        Group {
            Text("Network").font(.subheadline).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(fmtSpeed(s.netUploadBps), systemImage: "arrow.up").foregroundColor(.green)
                    Spacer()
                    Label(fmtSpeed(s.netDownloadBps), systemImage: "arrow.down").foregroundColor(.blue)
                }
                ForEach(s.networkInterfaces, id: \.name) { iface in
                    HStack {
                        Text(iface.name).font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text("↑ \(fmtSpeed(iface.uploadBps))  ↓ \(fmtSpeed(iface.downloadBps))")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
    }

    // ── 磁盘区块 ──
    @ViewBuilder
    private func diskSection(_ s: SystemSnapshot) -> some View {
        Group {
            Text("Disk").font(.subheadline).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(s.disks, id: \.mountPoint) { disk in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(disk.name).font(.caption)
                            Spacer()
                            Text("\(fmt(disk.usedBytes)) / \(fmt(disk.totalBytes))").font(.caption).foregroundColor(.secondary)
                        }
                        let ratio = Double(disk.usedBytes) / Double(max(1, disk.totalBytes))
                        ProgressView(value: ratio)
                            .accentColor(ratio > 0.85 ? .red : .accentColor)
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
    }

    // ── 电池区块 ──
    @ViewBuilder
    private func batterySection(_ b: BatterySnapshot) -> some View {
        Group {
            Text("Battery").font(.subheadline).foregroundColor(.secondary)
            HStack {
                Image(systemName: b.isCharging ? "battery.100.bolt" : "battery.75")
                    .foregroundColor(b.chargePercent < 20 ? .red : .green)
                Text(String(format: "%.0f%%", b.chargePercent))
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Health: \(String(format: "%.0f%%", b.healthPercent))").font(.caption)
                    if let cycles = b.cycleCount {
                        Text("Cycles: \(cycles)").font(.caption).foregroundColor(.secondary)
                    }
                    if let tte = b.timeToEmptySecs, !b.isCharging {
                        Text(formatTime(tte) + " remaining").font(.caption).foregroundColor(.secondary)
                    }
                    if let ttf = b.timeToFullSecs, b.isCharging {
                        Text(formatTime(ttf) + " to full").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
    }

    // ── 温度传感器区块 ──
    @ViewBuilder
    private func temperatureSection(_ s: SystemSnapshot) -> some View {
        Group {
            Text("Temperatures").font(.subheadline).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(s.temperatures, id: \.label) { t in
                    HStack {
                        Text(t.label).font(.caption)
                        Spacer()
                        Text(String(format: "%.1f°C", t.celsius))
                            .font(.caption)
                            .foregroundColor(t.celsius > 90 ? .red : t.celsius > 70 ? .orange : .primary)
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
    }

    // ── 进程排行区块 ──
    @ViewBuilder
    private func processSection(_ s: SystemSnapshot) -> some View {
        Group {
            Text("Top Processes").font(.subheadline).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("By CPU").font(.caption).foregroundColor(.secondary)
                ForEach(s.topCpuProcesses, id: \.pid) { p in
                    HStack {
                        Text(p.name).font(.caption)
                        Spacer()
                        Text(String(format: "%.1f%%", p.cpuUsage)).font(.caption).foregroundColor(.secondary)
                    }
                }
                Divider()
                Text("By Memory").font(.caption).foregroundColor(.secondary)
                ForEach(s.topMemProcesses, id: \.pid) { p in
                    HStack {
                        Text(p.name).font(.caption)
                        Spacer()
                        Text(fmt(p.memBytes)).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
    }

    // ── 辅助方法 ──

    private func coreColor(_ usage: Float) -> Color {
        switch usage {
        case 80...: return .red
        case 50...: return .orange
        default: return .blue
        }
    }

    private func fmt(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    private func fmtSpeed(_ bps: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bps), countStyle: .file) + "/s"
    }

    private func formatTime(_ secs: Int64) -> String {
        let h = secs / 3600
        let m = (secs % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 3: Commit**

```bash
git add platforms/macos/Atlas/ContentView.swift
git commit -m "feat(macos): redesign monitoring UI with per-core CPU, memory breakdown, disk, battery, temperatures, top processes"
```

---

## Self-Review

**1. Spec Coverage:**

| 功能 | 对应 Task |
|------|-----------|
| CPU 全局 + 每核 + 频率 | Task 2 |
| 内存：已用/空闲/可用/交换 | Task 2 |
| 进程排行（CPU + 内存 Top 5）| Task 2 |
| 网络每接口 | Task 2 |
| 磁盘卷空间 | Task 3 |
| 电池状态 | Task 4 |
| 温度传感器 | Task 5 |
| FFI 全量类型 | Task 6 |
| SwiftUI 富信息 UI | Task 7 |

**2. 类型一致性：** `CpuCoreSnapshot`、`ProcessSnapshot`、`NetworkInterfaceSnapshot`、`DiskSnapshot`、`BatterySnapshot`、`TemperatureSnapshot` 在 models.rs / atlas.udl / lib.rs / ContentView.swift 四处字段名与类型完全对应。

**3. 已知限制：**
- macOS 温度传感器：受 SIP 限制，`sysinfo Components` 可能返回空列表，属正常现象。
- 磁盘 I/O 读写速率（非空间）未包含，需 `iostat` shell 或 IOKit，留作后续。
- GPU 利用率需 Metal/IOKit 私有 API，留作后续。

---

Plan complete and saved to `docs/superpowers/plans/2026-05-09-enhanced-monitoring.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**

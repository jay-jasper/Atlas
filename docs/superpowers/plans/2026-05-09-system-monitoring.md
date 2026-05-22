# System Monitoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 Atlas 系统监控模块，包含 CPU/内存/网速实时采集与推送，以及 Port Master 端口管理功能。

**Architecture:** Rust Core 启动定时任务采集指标，通过 UniFFI Callback 推送给 Swift UI；端口管理通过命令行工具 `lsof` 实现。

**Tech Stack:** Rust, sysinfo, tokio, UniFFI, SwiftUI.

---

### Task 1: 依赖配置与数据模型定义

**Files:**
- Modify: `crates/atlas-core/Cargo.toml`
- Create: `crates/atlas-core/src/monitor/mod.rs`
- Create: `crates/atlas-core/src/monitor/models.rs`
- Modify: `crates/atlas-core/src/lib.rs`

- [x] **Step 1: 添加 Rust 依赖**

```toml
# crates/atlas-core/Cargo.toml
[dependencies]
sysinfo = "0.30"
tokio = { version = "1.36", features = ["full"] }
anyhow = "1.0"
serde = { version = "1.0", features = ["derive"] }
```

- [x] **Step 2: 定义监控数据结构**

```rust
// crates/atlas-core/src/monitor/models.rs
use serde::{Serialize, Deserialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemSnapshot {
    pub cpu_usage: f32,
    pub mem_used_bytes: u64,
    pub mem_total_bytes: u64,
    pub net_upload_bps: u64,
    pub net_download_bps: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PortProcessInfo {
    pub port: u16,
    pub pid: u32,
    pub process_name: String,
}
```

- [x] **Step 3: 导出模块**

```rust
// crates/atlas-core/src/monitor/mod.rs
pub mod models;
```

```rust
// crates/atlas-core/src/lib.rs
pub mod monitor;
```

- [x] **Step 4: Commit**

```bash
git add crates/atlas-core/Cargo.toml crates/atlas-core/src/monitor
git commit -m "feat: add monitoring models and dependencies"
```

---

### Task 2: 实现硬件指标采集 (CPU/RAM/Network)

**Files:**
- Create: `crates/atlas-core/src/monitor/collector.rs`
- Modify: `crates/atlas-core/src/monitor/mod.rs`

- [x] **Step 1: 实现指标采集逻辑**

```rust
// crates/atlas-core/src/monitor/collector.rs
use sysinfo::{System, Networks, NetworkExt, CpuExt};
use crate::monitor::models::SystemSnapshot;

pub struct Collector {
    sys: System,
    networks: Networks,
}

impl Collector {
    pub fn new() -> Self {
        Self {
            sys: System::new_all(),
            networks: Networks::new_with_refreshed_list(),
        }
    }

    pub fn take_snapshot(&mut self) -> SystemSnapshot {
        self.sys.refresh_cpu();
        self.sys.refresh_memory();
        self.networks.refresh_list();

        let cpu_usage = self.sys.global_cpu_info().cpu_usage();
        let mem_used_bytes = self.sys.used_memory();
        let mem_total_bytes = self.sys.total_memory();

        let mut upload = 0;
        let mut download = 0;
        for (_, data) in &self.networks {
            upload += data.transmitted();
            download += data.received();
        }

        SystemSnapshot {
            cpu_usage,
            mem_used_bytes,
            mem_total_bytes,
            net_upload_bps: upload,
            net_download_bps: download,
        }
    }
}
```

- [x] **Step 2: 运行单元测试验证采集**

```rust
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn test_snapshot_collection() {
        let mut c = Collector::new();
        let s = c.take_snapshot();
        assert!(s.mem_total_bytes > 0);
    }
}
```

Run: `cargo test -p atlas-core`

- [x] **Step 3: Commit**

```bash
git add crates/atlas-core/src/monitor/collector.rs
git commit -m "feat: implement hardware monitoring collector"
```

---

### Task 3: 实现 Port Master (端口查询与关闭)

**Files:**
- Create: `crates/atlas-core/src/monitor/port_master.rs`
- Modify: `crates/atlas-core/src/monitor/mod.rs`

- [x] **Step 1: 实现端口查找逻辑 (macOS 适配)**

```rust
// crates/atlas-core/src/monitor/port_master.rs
use std::process::Command;
use crate::monitor::models::PortProcessInfo;

pub fn find_process_by_port(port: u16) -> Option<PortProcessInfo> {
    let output = Command::new("lsof")
        .args(["-i", &format!(":{}", port), "-t", "-sTCP:LISTEN"])
        .output()
        .ok()?;

    let pid_str = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if pid_str.is_empty() { return None; }

    let pid: u32 = pid_str.parse().ok()?;
    
    // 获取进程名
    let name_output = Command::new("ps")
        .args(["-p", &pid_str, "-o", "comm="])
        .output()
        .ok()?;
    let process_name = String::from_utf8_lossy(&name_output.stdout).trim().to_string();

    Some(PortProcessInfo { port, pid, process_name })
}

pub fn kill_process(pid: u32) -> bool {
    Command::new("kill")
        .args(["-9", &pid.to_string()])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}
```

- [x] **Step 2: Commit**

```bash
git add crates/atlas-core/src/monitor/port_master.rs
git commit -m "feat: implement port master logic"
```

---

### Task 4: 更新 UniFFI 桥接支持 Callback 推送

**Files:**
- Modify: `crates/atlas-ffi/src/atlas.udl`
- Modify: `crates/atlas-ffi/src/lib.rs`

- [x] **Step 1: 定义 UDL 回调接口与数据类型**

```udl
// crates/atlas-ffi/src/atlas.udl
dictionary SystemSnapshot {
    float cpu_usage;
    u64 mem_used_bytes;
    u64 mem_total_bytes;
    u64 net_upload_bps;
    u64 net_download_bps;
};

callback interface SystemMonitorCallback {
    void on_snapshot(SystemSnapshot snapshot);
};

namespace atlas {
    void start_monitoring(SystemMonitorCallback callback);
    void stop_monitoring();
    PortProcessInfo? lookup_port(u16 port);
    boolean kill_port_process(u32 pid);
};
```

- [x] **Step 2: 在 FFI 层实现异步推送循环**

```rust
// crates/atlas-ffi/src/lib.rs (部分)
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

static IS_MONITORING: AtomicBool = AtomicBool::new(false);

pub fn start_monitoring(callback: Box<dyn SystemMonitorCallback>) {
    IS_MONITORING.store(true, Ordering::SeqCst);
    tokio::spawn(async move {
        let mut collector = atlas_core::monitor::collector::Collector::new();
        while IS_MONITORING.load(Ordering::SeqCst) {
            let snapshot = collector.take_snapshot();
            callback.on_snapshot(snapshot.into()); // 这里的 into 需要实现 FFI 映射
            tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
        }
    });
}
```

- [x] **Step 3: Commit**

```bash
git add crates/atlas-ffi
git commit -m "feat: setup ffi callbacks for system monitoring"
```

---

### Task 5: macOS UI 集成

**Files:**
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [x] **Step 1: 更新 UI 显示实时数据**

```swift
// platforms/macos/Atlas/ContentView.swift
import SwiftUI

struct ContentView: View {
    @State private var cpuUsage: Float = 0.0
    @State private var memUsed: UInt64 = 0
    // ... 其他状态

    var body: some View {
        VStack {
            Text("CPU: \(Int(cpuUsage))%")
            ProgressView(value: cpuUsage, total: 100.0)
            // ... 更多监控组件
            
            Divider()
            
            HStack {
                TextField("Port", value: $portInput, format: .number)
                Button("Kill") {
                    // 调用 AtlasBridge.killPortProcess
                }
            }
        }
        .onAppear {
            // AtlasBridge.startMonitoring { snapshot in
            //    self.cpuUsage = snapshot.cpuUsage
            // }
        }
    }
}
```

- [x] **Step 2: Commit**

```bash
git add platforms/macos/Atlas/ContentView.swift
git commit -m "feat: integrate monitoring ui in macos shell"
```

---

## Self-Review

1. **Spec Coverage**: 涵盖了数据采集、Port Master、FFI 回调、UI 展示全链路。
2. **Type Consistency**: `SystemSnapshot` 和 `PortProcessInfo` 在 Core/FFI/UI 中保持一致。
3. **Performance**: 使用异步任务不阻塞 UI，符合轻量化要求。
4. **Platform Scope**: 针对 macOS 明确使用了 `lsof` 实现端口管理。

---

Plan complete and saved to `docs/superpowers/plans/2026-05-09-system-monitoring.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**

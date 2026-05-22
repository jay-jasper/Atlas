# Atlas 基础框架搭建 (Scaffolding) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 搭建 Atlas 的跨平台基础架构，实现 Rust 核心与 macOS 原生 UI (SwiftUI) 的双向通信，并包含基础的功能选配引擎。

**Architecture:** 采用 Native Host / Shared Core 模式。Rust 编写核心逻辑与模块管理引擎，通过 UniFFI 生成 Swift 绑定；macOS 应用使用 SwiftUI 构建菜单栏入口。

**Tech Stack:** Rust (Core), SwiftUI (macOS UI), UniFFI (Bridge), SQLite (Timeline Storage).

---

### Task 1: 项目目录结构与 Rust 核心初始化

**Files:**
- Create: `Cargo.toml` (Workspace)
- Create: `crates/atlas-core/Cargo.toml`
- Create: `crates/atlas-core/src/lib.rs`
- Create: `crates/atlas-ffi/Cargo.toml`
- Create: `crates/atlas-ffi/src/lib.rs`

- [x] **Step 1: 创建 Workspace 配置文件**

```toml
# Cargo.toml
[workspace]
members = [
    "crates/atlas-core",
    "crates/atlas-ffi",
]
resolver = "2"
```

- [x] **Step 2: 初始化 atlas-core (核心逻辑层)**

```rust
// crates/atlas-core/src/lib.rs
pub struct AtlasCore {
    pub version: String,
}

impl AtlasCore {
    pub fn new() -> Self {
        Self {
            version: "0.1.0".to_string(),
        }
    }

    pub fn get_status(&self) -> String {
        format!("Atlas Core v{} is running", self.version)
    }
}
```

- [x] **Step 3: 运行测试验证核心逻辑**

Run: `cargo test -p atlas-core`
Expected: PASS

- [x] **Step 4: Commit**

```bash
git add Cargo.toml crates/atlas-core
git commit -m "chore: initialize rust workspace and atlas-core"
```

---

### Task 2: UniFFI 桥接层配置

**Files:**
- Modify: `crates/atlas-ffi/Cargo.toml`
- Create: `crates/atlas-ffi/src/atlas.udl`
- Modify: `crates/atlas-ffi/src/lib.rs`

- [x] **Step 1: 配置 UniFFI 依赖**

```toml
# crates/atlas-ffi/Cargo.toml
[package]
name = "atlas-ffi"
version = "0.1.0"
edition = "2021"

[dependencies]
atlas-core = { path = "../atlas-core" }
uniffi = { version = "0.28", features = ["cli"] }

[build-dependencies]
uniffi = { version = "0.28", features = ["build"] }

[lib]
crate-type = ["staticlib", "cdylib"]
```

- [x] **Step 2: 编写接口定义文件 (UDL)**

```udl
// crates/atlas-ffi/src/atlas.udl
namespace atlas {
    string get_core_status();
};
```

- [x] **Step 3: 实现 FFI 导出函数**

```rust
// crates/atlas-ffi/src/lib.rs
use atlas_core::AtlasCore;

uniffi::include_scaffolding!("atlas");

pub fn get_core_status() -> String {
    let core = AtlasCore::new();
    core.get_status()
}
```

- [x] **Step 4: 编译并生成绑定代码**

Run: `cargo build -p atlas-ffi`
Expected: 生成静态库及 UniFFI 中间产物。

- [x] **Step 5: Commit**

```bash
git add crates/atlas-ffi
git commit -m "feat: setup uniffi bridge for atlas"
```

---

### Task 3: macOS SwiftUI 菜单栏壳程序

**Files:**
- Create: `platforms/macos/Atlas/AtlasApp.swift`
- Create: `platforms/macos/Atlas/ContentView.swift`

- [x] **Step 1: 创建基础菜单栏应用 (SwiftUI)**

```swift
// platforms/macos/Atlas/AtlasApp.swift
import SwiftUI

@main
struct AtlasApp: App {
    @State private var statusText: String = "Initializing..."

    var body: some Scene {
        MenuBarExtra("Atlas", systemImage: "square.stack.3d.up.fill") {
            Text(statusText)
                .onAppear {
                    // 这里稍后调用 Rust 接口
                    statusText = "Atlas is Ready"
                }
            Button("Settings") {
                NSApp.activate(ignoringOtherApps: true)
                // 打开选配界面
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
```

- [x] **Step 2: 验证编译 (模拟)**

由于需要 Xcode 环境，此处仅验证文件结构。

- [x] **Step 3: Commit**

```bash
git add platforms/macos/Atlas
git commit -m "feat: add basic macos menu bar shell"
```

---

### Task 4: 实现动态功能选配引擎 (Feature Manager)

**Files:**
- Modify: `crates/atlas-core/src/lib.rs`
- Create: `crates/atlas-core/src/features.rs`

- [x] **Step 1: 定义模块特性与状态**

```rust
// crates/atlas-core/src/features.rs
use std::collections::HashMap;

pub enum FeatureStatus {
    Enabled,
    Disabled,
}

pub struct FeatureManager {
    features: HashMap<String, FeatureStatus>,
}

impl FeatureManager {
    pub fn new() -> Self {
        let mut features = HashMap::new();
        features.insert("monitoring".to_string(), FeatureStatus::Disabled);
        features.insert("screenshot".to_string(), FeatureStatus::Disabled);
        // Port Master belongs to the monitoring feature instead of a separate toggle.
        Self { features }
    }

    pub fn toggle_feature(&mut self, name: &str, enabled: bool) {
        let status = if enabled { FeatureStatus::Enabled } else { FeatureStatus::Disabled };
        self.features.insert(name.to_string(), status);
        // 实际逻辑：这里会启动或关闭后台线程
    }
}
```

- [x] **Step 2: 在核心中集成管理器**

```rust
// crates/atlas-core/src/lib.rs (部分更新)
pub mod features;
use features::FeatureManager;

pub struct AtlasCore {
    pub version: String,
    pub feature_manager: FeatureManager,
}
```

- [x] **Step 3: 运行测试**

Run: `cargo test -p atlas-core`
Expected: PASS

- [x] **Step 4: Commit**

```bash
git add crates/atlas-core/src/features.rs
git commit -m "feat: implement basic feature manager logic"
```

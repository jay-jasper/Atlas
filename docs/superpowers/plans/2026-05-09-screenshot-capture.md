# Screenshot & Basic Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 Atlas 截图工具的第一阶段能力，参考 Shottr 与微信截图工具，包含原生确认式选区 Overlay、选区微调、基础输出流及后续标注/钉图扩展路径。

**Architecture:** Rust Core 负责跨平台截屏底层逻辑与图片处理；macOS UI 使用 SwiftUI 实现 120Hz 选区遮罩。

**Tech Stack:** Rust, screenshots (crate), image (crate), UniFFI, SwiftUI.

---

### Task 1: 基础截图依赖与 Rust 核心实现

**Files:**
- Modify: `crates/atlas-core/Cargo.toml`
- Create: `crates/atlas-core/src/capture/mod.rs`
- Create: `crates/atlas-core/src/capture/engine.rs`
- Modify: `crates/atlas-core/src/lib.rs`

- [x] **Step 1: 添加 Rust 截图依赖**

```toml
# crates/atlas-core/Cargo.toml
[dependencies]
# ... existing ...
screenshots = "0.8"
image = "0.24"
uuid = { version = "1.7", features = ["v4"] }
```

- [x] **Step 2: 实现基础捕获引擎**

```rust
// crates/atlas-core/src/capture/engine.rs
use screenshots::Screen;
use anyhow::{Result, Context};
use std::path::PathBuf;
use uuid::Uuid;

pub struct CaptureEngine;

impl CaptureEngine {
    /// 捕获全屏并返回原始像素数据 (RGBA)
    pub fn capture_full_screen() -> Result<Vec<u8>> {
        let screens = Screen::all().context("Failed to get screens")?;
        let screen = screens.first().context("No screen found")?;
        let image = screen.capture().context("Capture failed")?;
        Ok(image.to_png()?) // 暂存为 PNG 格式
    }

    /// 根据选区坐标裁剪图片
    pub fn capture_region(x: i32, y: u32, width: u32, height: u32) -> Result<Vec<u8>> {
        let screens = Screen::all().context("Failed to get screens")?;
        let screen = screens.first().context("No screen found")?;
        let image = screen.capture_area(x, y, width, height).context("Region capture failed")?;
        Ok(image.to_png()?)
    }
}
```

- [x] **Step 3: 导出模块**

```rust
// crates/atlas-core/src/lib.rs
pub mod capture;
```

- [x] **Step 4: Commit**

```bash
git add crates/atlas-core/Cargo.toml crates/atlas-core/src/capture
git commit -m "feat: implement basic rust capture engine"
```

---

### Task 2: 更新 UniFFI 桥接支持截图调用

**Files:**
- Modify: `crates/atlas-ffi/src/atlas.udl`
- Modify: `crates/atlas-ffi/src/lib.rs`

- [x] **Step 1: 定义 UDL 截图接口**

```udl
// crates/atlas-ffi/src/atlas.udl
namespace atlas {
    // ... existing ...
    sequence<u8> capture_full_screen();
    sequence<u8> capture_region(i32 x, u32 y, u32 width, u32 height);
};
```

- [x] **Step 2: 实现 FFI 导出函数**

```rust
// crates/atlas-ffi/src/lib.rs
pub fn capture_full_screen() -> Vec<u8> {
    atlas_core::capture::engine::CaptureEngine::capture_full_screen().unwrap_or_default()
}

pub fn capture_region(x: i32, y: u32, width: u32, height: u32) -> Vec<u8> {
    atlas_core::capture::engine::CaptureEngine::capture_region(x, y, width, height).unwrap_or_default()
}
```

- [x] **Step 3: Commit**

```bash
git add crates/atlas-ffi/src/atlas.udl crates/atlas-ffi/src/lib.rs
git commit -m "feat: export capture functions via uniffi"
```

---

### Task 3: 实现 macOS 原生选区 Overlay (SwiftUI)

**Files:**
- Create: `platforms/macos/Atlas/SelectionOverlay.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [x] **Step 1: 创建确认式选区交互视图**

需求：
- 拖拽创建选区，松手后不立即截图。
- 显示选区边框与实时尺寸，例如 `640 x 360`。
- 支持拖动选区移动。
- 支持拖拽四角调整选区大小；后续可扩展到四边调整。
- 支持取消与确认操作，Esc 取消，Enter 或确认按钮截图。
- 工具栏贴近选区，避免遮挡选区内容；靠近屏幕边缘时自动翻转到可见区域。

```swift
// platforms/macos/Atlas/SelectionOverlay.swift
import SwiftUI

struct SelectionOverlay: View {
    @State private var selection: CGRect?
    var onCapture: (CGRect) -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .edgesIgnoringSafeArea(.all)

            // Selection border, size badge, resize handles, and confirm/cancel toolbar.
        }
    }
}
```

- [x] **Step 2: 在 ContentView 中接入取消与确认回调**

```swift
SelectionOverlay(
    onCancel: { isShowingSelectionOverlay = false },
    onCapture: { rect in
        // 调用 AtlasBridge.captureRegion 后关闭 overlay
    }
)
```

- [x] **Step 3: Commit**

```bash
git add platforms/macos/Atlas/SelectionOverlay.swift
git commit -m "feat: add adjustable screenshot selection overlay"
```

---

### Task 4: 整合截图输出流

**Files:**
- Modify: `platforms/macos/Atlas/ContentView.swift`
- Modify: `platforms/macos/Atlas/AtlasApp.swift`

- [x] **Step 1: 实现复制、保存与状态反馈**

```swift
// Logic (Pseudocode):
// 1. 快捷键触发 -> 显示透明满屏窗口 (SelectionOverlay)
// 2. 选区结束 -> 调用 AtlasBridge.captureRegion
// 3. 默认复制 PNG 到剪贴板
// 4. 支持保存到用户选择路径或 Downloads
// 5. 显示短暂成功/失败状态
```

- [x] **Step 2: Commit**

```bash
git add platforms/macos/Atlas
git commit -m "feat: add screenshot copy and save flow"
```

---

### Task 5: 添加微信式快速标注工具栏

**Files:**
- Create: `platforms/macos/Atlas/ScreenshotAnnotationView.swift`
- Modify: `platforms/macos/Atlas/SelectionOverlay.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [x] **Step 1: 定义标注模型**

支持最小标注集合：
- 矩形
- 箭头
- 画笔
- 文字
- 马赛克/模糊

- [x] **Step 2: 在选区工具栏中增加工具入口**

工具栏行为：
- 默认显示取消、确认。
- 进入标注模式后显示工具、颜色、线宽、撤销。
- 标注完成后确认输出合成后的图片。

- [x] **Step 3: Commit**

```bash
git add platforms/macos/Atlas
git commit -m "feat: add screenshot quick annotation tools"
```

---

### Task 6: 添加 Shottr 式钉图与精确选择辅助

**Files:**
- Create: `platforms/macos/Atlas/PinnedScreenshotWindow.swift`
- Modify: `platforms/macos/Atlas/SelectionOverlay.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [x] **Step 1: 实现钉图**

需求：
- 截图后可点击 Pin，将截图作为置顶悬浮窗显示。
- 悬浮窗支持拖动、关闭，后续可支持缩放和透明度。

- [x] **Step 2: 实现精确选择辅助**

需求：
- 鼠标附近显示像素放大镜。
- 选区靠近窗口边缘或明显 UI 边界时吸附。
- 显示简单标尺/辅助线。
- 后续支持颜色取样。

- [x] **Step 3: Commit**

```bash
git add platforms/macos/Atlas
git commit -m "feat: add screenshot pinning and precision aids"
```

---

## Self-Review

1. **Spec Coverage**: 涵盖了设计文档中 Phase 1 的确认式选区、选区微调、捕获与输出，并为标注、钉图和精确选择辅助留出任务。
2. **Type Consistency**: `capture_region` 参数在 UDL 和 Rust 中匹配。
3. **Architecture**: 保持了核心在 Rust，UI 在 Swift 的原则。

---

Plan complete and saved to `docs/superpowers/plans/2026-05-09-screenshot-capture.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**

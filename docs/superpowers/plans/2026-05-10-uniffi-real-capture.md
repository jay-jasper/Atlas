# UniFFI Real Capture Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Swift screenshot mock path with real Rust UniFFI capture calls for full-screen and region screenshots while keeping deterministic tests.

**Architecture:** Rust `atlas-ffi` remains the source of truth for capture APIs. A small workspace bindgen runner generates Swift/C bindings from the compiled `atlas-ffi` library, Xcode links the generated static library/module, and Swift calls a focused `AtlasCaptureService` instead of generating mock PNGs inside `AtlasBridge`.

**Tech Stack:** Rust, UniFFI 0.28.3, SwiftUI, AppKit, Xcode project targets, XCTest.

---

## Scope Check

This plan covers only real screenshot capture integration through UniFFI:

- Generate and commit Swift bindings, C header/modulemap, and macOS static library artifacts.
- Link those artifacts into the macOS app target.
- Replace `AtlasBridge.captureRegion` and `AtlasBridge.captureFullScreen` mock capture with real UniFFI calls.
- Convert the selection overlay rectangle into main-screen pixel coordinates.
- Surface capture failures clearly in the screenshot UI.

This plan does not implement OCR, translation, scrolling capture, multi-display capture, monitoring UniFFI replacement, or port master UniFFI replacement.

---

## File Structure

- Create: `tools/uniffi-swift-bindgen/Cargo.toml`
  - Small local Rust binary for generating Swift bindings with the exact UniFFI version already locked by the workspace.
- Create: `tools/uniffi-swift-bindgen/src/main.rs`
  - Calls `uniffi_bindgen::bindings::swift::generate_swift_bindings`.
- Modify: `Cargo.toml`
  - Adds `tools/uniffi-swift-bindgen` to workspace members.
- Create: `scripts/generate_uniffi_swift.sh`
  - Builds `atlas-ffi`, runs the bindgen runner, and copies generated artifacts to `platforms/macos/Generated/AtlasFFI`.
- Create/Update generated files under `platforms/macos/Generated/AtlasFFI/`
  - `atlas.swift`
  - `atlasFFI.h`
  - `atlas_ffi.modulemap`
  - `libatlas_ffi.a`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Adds generated Swift source, generated static library, library search path, and Swift include path.
- Create: `platforms/macos/Atlas/ScreenCaptureCoordinateMapper.swift`
  - Converts selection-window point rectangles into Rust capture pixel rectangles.
- Create: `platforms/macos/Atlas/AtlasCaptureService.swift`
  - Owns real capture calls, capture errors, and testable mock hooks.
- Modify: `platforms/macos/Atlas/AtlasBridge.swift`
  - Removes screenshot mock PNG generation from production capture path and delegates to `AtlasCaptureService`.
- Modify: `platforms/macos/Atlas/ContentView.swift`
  - Handles throwing capture calls and displays error status.
- Test: `platforms/macos/AtlasTests/ScreenCaptureCoordinateMapperTests.swift`
  - Verifies point-to-pixel conversion.
- Test: `platforms/macos/AtlasTests/AtlasCaptureServiceTests.swift`
  - Verifies service error propagation and mock injection without requiring Screen Recording permission.

---

### Task 1: Local UniFFI Swift Bindgen Runner

**Files:**
- Modify: `Cargo.toml`
- Create: `tools/uniffi-swift-bindgen/Cargo.toml`
- Create: `tools/uniffi-swift-bindgen/src/main.rs`

- [ ] **Step 1: Add the bindgen runner crate to the workspace**

Update the root `Cargo.toml`:

```toml
[workspace]
members = [
    "crates/atlas-core",
    "crates/atlas-ffi",
    "tools/uniffi-swift-bindgen",
]
resolver = "2"
```

- [ ] **Step 2: Add the bindgen runner manifest**

Create `tools/uniffi-swift-bindgen/Cargo.toml`:

```toml
[package]
name = "uniffi-swift-bindgen"
version = "0.1.0"
edition = "2021"

[dependencies]
anyhow = "1.0"
camino = "1.1"
uniffi_bindgen = { version = "0.28.3", features = ["cargo-metadata"] }
```

- [ ] **Step 3: Add the bindgen runner implementation**

Create `tools/uniffi-swift-bindgen/src/main.rs`:

```rust
use anyhow::{bail, Context, Result};
use camino::Utf8PathBuf;
use std::env;
use uniffi_bindgen::bindings::swift::{generate_swift_bindings, SwiftBindingsOptions};

fn main() -> Result<()> {
    let args = env::args().skip(1).collect::<Vec<_>>();
    if args.len() != 2 {
        bail!("usage: uniffi-swift-bindgen <library-path> <output-dir>");
    }

    let library_path = Utf8PathBuf::from(&args[0]);
    let out_dir = Utf8PathBuf::from(&args[1]);

    if !library_path.exists() {
        bail!("library path does not exist: {library_path}");
    }

    std::fs::create_dir_all(&out_dir)
        .with_context(|| format!("failed to create output directory {out_dir}"))?;

    generate_swift_bindings(SwiftBindingsOptions {
        generate_swift_sources: true,
        generate_headers: true,
        generate_modulemap: true,
        library_path,
        out_dir,
        xcframework: false,
        module_name: Some("AtlasFFI".to_string()),
        modulemap_filename: Some("atlas_ffi.modulemap".to_string()),
        metadata_no_deps: false,
    })
}
```

- [ ] **Step 4: Verify the runner builds**

Run:

```bash
cargo check -p uniffi-swift-bindgen
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Cargo.toml tools/uniffi-swift-bindgen
git commit -m "build(uniffi): add swift bindgen runner"
```

---

### Task 2: Generate Swift Bindings and Rust Library Artifacts

**Files:**
- Create: `scripts/generate_uniffi_swift.sh`
- Create/Update: `platforms/macos/Generated/AtlasFFI/atlas.swift`
- Create/Update: `platforms/macos/Generated/AtlasFFI/atlasFFI.h`
- Create/Update: `platforms/macos/Generated/AtlasFFI/atlas_ffi.modulemap`
- Create/Update: `platforms/macos/Generated/AtlasFFI/libatlas_ffi.a`

- [ ] **Step 1: Add the generation script**

Create `scripts/generate_uniffi_swift.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/platforms/macos/Generated/AtlasFFI"
LIB_DYLIB="$ROOT_DIR/target/release/libatlas_ffi.dylib"
LIB_STATIC="$ROOT_DIR/target/release/libatlas_ffi.a"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

cargo build -p atlas-ffi --release
cargo run -p uniffi-swift-bindgen -- "$LIB_DYLIB" "$OUT_DIR"

cp "$LIB_STATIC" "$OUT_DIR/libatlas_ffi.a"

test -f "$OUT_DIR/atlas.swift"
test -f "$OUT_DIR/atlasFFI.h"
test -f "$OUT_DIR/atlas_ffi.modulemap"
test -f "$OUT_DIR/libatlas_ffi.a"

echo "Generated UniFFI Swift artifacts in $OUT_DIR"
```

- [ ] **Step 2: Make the script executable**

Run:

```bash
chmod +x scripts/generate_uniffi_swift.sh
```

Expected: command exits 0.

- [ ] **Step 3: Generate artifacts**

Run:

```bash
./scripts/generate_uniffi_swift.sh
```

Expected:

```text
Generated UniFFI Swift artifacts in /Users/lee/workspaces/ai/Atlas/platforms/macos/Generated/AtlasFFI
```

- [ ] **Step 4: Inspect the generated Swift API names**

Run:

```bash
rg -n "func capture|enum AtlasError|struct FeatureEntry" platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: output includes generated throwing functions for `captureFullScreen()` and `captureRegion(x:y:width:height:)`, plus generated model/error types.

- [ ] **Step 5: Commit**

```bash
git add scripts/generate_uniffi_swift.sh platforms/macos/Generated/AtlasFFI
git commit -m "build(uniffi): generate swift bindings for atlas ffi"
```

---

### Task 3: Link Generated UniFFI Artifacts Into Xcode

**Files:**
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add generated files to Xcode project**

Edit `platforms/macos/Atlas.xcodeproj/project.pbxproj` so:

- `platforms/macos/Generated/AtlasFFI/atlas.swift` is in the `Atlas` target Sources build phase.
- `platforms/macos/Generated/AtlasFFI/libatlas_ffi.a` is in the `Atlas` target Frameworks build phase.
- `platforms/macos/Generated/AtlasFFI/atlasFFI.h` and `atlas_ffi.modulemap` are file references under a `Generated/AtlasFFI` group.

Use the same object style already present in the project. Add deterministic new IDs with the existing `83CBBA...` prefix pattern.

- [ ] **Step 2: Add Swift include and library paths**

In the `Atlas` target Debug and Release build settings in `project.pbxproj`, set or append:

```text
SWIFT_INCLUDE_PATHS = "$(SRCROOT)/Generated/AtlasFFI";
LIBRARY_SEARCH_PATHS = "$(SRCROOT)/Generated/AtlasFFI";
OTHER_LDFLAGS = (
    "$(inherited)",
    "-lresolv",
);
```

Keep existing settings intact. If `OTHER_LDFLAGS` already exists, append `-lresolv` rather than replacing existing flags.

- [ ] **Step 3: Build the app**

Run:

```bash
xcodebuild -project platforms/macos/Atlas.xcodeproj -scheme Atlas -configuration Debug build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "build(macos): link atlas uniffi artifacts"
```

---

### Task 4: Coordinate Mapping for Region Capture

**Files:**
- Create: `platforms/macos/Atlas/ScreenCaptureCoordinateMapper.swift`
- Create: `platforms/macos/AtlasTests/ScreenCaptureCoordinateMapperTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing tests**

Create `platforms/macos/AtlasTests/ScreenCaptureCoordinateMapperTests.swift`:

```swift
import XCTest
@testable import Atlas

final class ScreenCaptureCoordinateMapperTests: XCTestCase {
    func testMapsPointRectToPixelRect() {
        let rect = CGRect(x: 10.25, y: 20.5, width: 30.25, height: 40.5)

        let region = ScreenCaptureCoordinateMapper.pixelRegion(fromSelectionRect: rect, backingScaleFactor: 2)

        XCTAssertEqual(region.x, 20)
        XCTAssertEqual(region.y, 41)
        XCTAssertEqual(region.width, 61)
        XCTAssertEqual(region.height, 81)
    }

    func testClampsToAtLeastOnePixel() {
        let rect = CGRect(x: 0, y: 0, width: 0.2, height: 0.2)

        let region = ScreenCaptureCoordinateMapper.pixelRegion(fromSelectionRect: rect, backingScaleFactor: 2)

        XCTAssertEqual(region.width, 1)
        XCTAssertEqual(region.height, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenCaptureCoordinateMapperTests
```

Expected: FAIL because `ScreenCaptureCoordinateMapper` does not exist.

- [ ] **Step 3: Add mapper implementation**

Create `platforms/macos/Atlas/ScreenCaptureCoordinateMapper.swift`:

```swift
import CoreGraphics

struct ScreenCapturePixelRegion: Equatable {
    let x: Int32
    let y: Int32
    let width: UInt32
    let height: UInt32
}

enum ScreenCaptureCoordinateMapper {
    static func pixelRegion(
        fromSelectionRect rect: CGRect,
        backingScaleFactor scale: CGFloat
    ) -> ScreenCapturePixelRegion {
        let safeScale = max(scale, 1)
        let standardized = rect.standardized.integral

        let x = Int32((standardized.minX * safeScale).rounded(.down))
        let y = Int32((standardized.minY * safeScale).rounded(.down))
        let width = UInt32(max(1, (standardized.width * safeScale).rounded(.up)))
        let height = UInt32(max(1, (standardized.height * safeScale).rounded(.up)))

        return ScreenCapturePixelRegion(x: x, y: y, width: width, height: height)
    }
}
```

- [ ] **Step 4: Add files to Xcode project**

Add `ScreenCaptureCoordinateMapper.swift` to the `Atlas` Sources build phase and `ScreenCaptureCoordinateMapperTests.swift` to the `AtlasTests` Sources build phase.

- [ ] **Step 5: Run tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenCaptureCoordinateMapperTests
```

Expected: PASS, 2 tests.

- [ ] **Step 6: Commit**

```bash
git add platforms/macos/Atlas/ScreenCaptureCoordinateMapper.swift platforms/macos/AtlasTests/ScreenCaptureCoordinateMapperTests.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add screen capture coordinate mapper"
```

---

### Task 5: Real Capture Service Wrapper

**Files:**
- Create: `platforms/macos/Atlas/AtlasCaptureService.swift`
- Create: `platforms/macos/AtlasTests/AtlasCaptureServiceTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write service tests with injected functions**

Create `platforms/macos/AtlasTests/AtlasCaptureServiceTests.swift`:

```swift
import XCTest
@testable import Atlas

final class AtlasCaptureServiceTests: XCTestCase {
    func testCaptureRegionUsesInjectedFunction() throws {
        let expected = Data([1, 2, 3])
        let service = AtlasCaptureService(
            captureFullScreen: { Data([9]) },
            captureRegion: { x, y, width, height in
                XCTAssertEqual(x, 10)
                XCTAssertEqual(y, 20)
                XCTAssertEqual(width, 30)
                XCTAssertEqual(height, 40)
                return expected
            }
        )

        let data = try service.captureRegion(.init(x: 10, y: 20, width: 30, height: 40))

        XCTAssertEqual(data, expected)
    }

    func testCaptureErrorsExposeMessage() {
        let service = AtlasCaptureService(
            captureFullScreen: { throw AtlasCaptureError.captureFailed("denied") },
            captureRegion: { _, _, _, _ in Data() }
        )

        XCTAssertThrowsError(try service.captureFullScreen()) { error in
            XCTAssertEqual(error.localizedDescription, "denied")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/AtlasCaptureServiceTests
```

Expected: FAIL because `AtlasCaptureService` does not exist.

- [ ] **Step 3: Add service implementation**

Create `platforms/macos/Atlas/AtlasCaptureService.swift`:

```swift
import Foundation

enum AtlasCaptureError: LocalizedError, Equatable {
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .captureFailed(let message):
            return message
        }
    }
}

struct AtlasCaptureService {
    var captureFullScreen: () throws -> Data
    var captureRegion: (Int32, Int32, UInt32, UInt32) throws -> Data

    func captureRegion(_ region: ScreenCapturePixelRegion) throws -> Data {
        try captureRegion(region.x, region.y, region.width, region.height)
    }
}

extension AtlasCaptureService {
    static let live = AtlasCaptureService(
        captureFullScreen: {
            do {
                return Data(try captureFullScreen())
            } catch {
                throw AtlasCaptureError.captureFailed(error.localizedDescription)
            }
        },
        captureRegion: { x, y, width, height in
            do {
                return Data(try captureRegion(x: x, y: y, width: width, height: height))
            } catch {
                throw AtlasCaptureError.captureFailed(error.localizedDescription)
            }
        }
    )
}
```

- [ ] **Step 4: Add files to Xcode project**

Add `AtlasCaptureService.swift` to the `Atlas` Sources build phase and `AtlasCaptureServiceTests.swift` to the `AtlasTests` Sources build phase.

- [ ] **Step 5: Run tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/AtlasCaptureServiceTests
```

Expected: PASS, 2 tests.

- [ ] **Step 6: Commit**

```bash
git add platforms/macos/Atlas/AtlasCaptureService.swift platforms/macos/AtlasTests/AtlasCaptureServiceTests.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat(macos): add atlas capture service"
```

---

### Task 6: Replace Screenshot Capture Mock Calls

**Files:**
- Modify: `platforms/macos/Atlas/AtlasBridge.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`
- Modify: `platforms/macos/AtlasTests/AtlasBridgeCaptureTests.swift`

- [ ] **Step 1: Update `AtlasBridge` screenshot functions**

In `platforms/macos/Atlas/AtlasBridge.swift`, remove the private `NSImage.atlasMockScreenshot` extension and replace screenshot methods with throwing live calls:

```swift
static var captureService: AtlasCaptureService = .live

static func captureRegion(x: Int32, y: Int32, width: UInt32, height: UInt32) throws -> Data {
    try captureService.captureRegion(x, y, width, height)
}

static func captureFullScreen() throws -> Data {
    try captureService.captureFullScreen()
}
```

Keep monitoring and port mock behavior unchanged.

- [ ] **Step 2: Update `ContentView.captureSelection`**

In `ContentView.captureSelection(_:)`, map the selection rect to pixels and handle errors:

```swift
private func captureSelection(_ rect: CGRect) {
    do {
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        let region = ScreenCaptureCoordinateMapper.pixelRegion(
            fromSelectionRect: rect,
            backingScaleFactor: scale
        )
        let data = try AtlasBridge.captureRegion(
            x: region.x,
            y: region.y,
            width: region.width,
            height: region.height
        )
        capturedScreenshot = CapturedScreenshot(
            pngData: data,
            rect: CGRect(x: 0, y: 0, width: Int(region.width), height: Int(region.height))
        )
        showStatus("Captured \(region.width)×\(region.height) px")
    } catch {
        showStatus(error.localizedDescription, kind: .error)
    }
}
```

- [ ] **Step 3: Update `ContentView.captureFullScreen`**

Replace optional capture with throwing capture:

```swift
private func captureFullScreen() {
    do {
        let data = try AtlasBridge.captureFullScreen()
        guard
            let bitmap = NSBitmapImageRep(data: data)
        else {
            showStatus("Captured full-screen image could not be decoded", kind: .error)
            return
        }

        capturedScreenshot = CapturedScreenshot(
            pngData: data,
            rect: CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        )
        showStatus("Captured full screen")
    } catch {
        showStatus(error.localizedDescription, kind: .error)
    }
}
```

- [ ] **Step 4: Update bridge tests to inject mock service**

Replace `platforms/macos/AtlasTests/AtlasBridgeCaptureTests.swift` with:

```swift
import AppKit
import XCTest
@testable import Atlas

final class AtlasBridgeCaptureTests: XCTestCase {
    override func tearDown() {
        AtlasBridge.captureService = .live
        super.tearDown()
    }

    func testBridgeRegionUsesCaptureService() throws {
        AtlasBridge.captureService = AtlasCaptureService(
            captureFullScreen: { Data([9]) },
            captureRegion: { x, y, width, height in
                XCTAssertEqual(x, 1)
                XCTAssertEqual(y, 2)
                XCTAssertEqual(width, 3)
                XCTAssertEqual(height, 4)
                return Data([1, 2, 3])
            }
        )

        let data = try AtlasBridge.captureRegion(x: 1, y: 2, width: 3, height: 4)

        XCTAssertEqual(data, Data([1, 2, 3]))
    }

    func testBridgeFullScreenUsesCaptureService() throws {
        AtlasBridge.captureService = AtlasCaptureService(
            captureFullScreen: { Data([7, 8]) },
            captureRegion: { _, _, _, _ in Data() }
        )

        let data = try AtlasBridge.captureFullScreen()

        XCTAssertEqual(data, Data([7, 8]))
    }
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/AtlasBridgeCaptureTests -only-testing:AtlasTests/AtlasCaptureServiceTests -only-testing:AtlasTests/ScreenCaptureCoordinateMapperTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add platforms/macos/Atlas/AtlasBridge.swift platforms/macos/Atlas/ContentView.swift platforms/macos/AtlasTests/AtlasBridgeCaptureTests.swift
git commit -m "feat(macos): route screenshot capture through uniffi"
```

---

### Task 7: Manual Permission and Real Capture Verification

**Files:**
- Modify: `docs/superpowers/plans/2026-05-10-uniffi-real-capture.md`

- [ ] **Step 1: Run Rust tests**

Run:

```bash
cargo test -p atlas-core -p atlas-ffi
```

Expected: PASS. Headless/screen-permission capture tests may return errors internally, but existing tests should not panic.

- [ ] **Step 2: Run Swift parse, build, and tests**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
xcodebuild -project platforms/macos/Atlas.xcodeproj -scheme Atlas -configuration Debug build
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'
```

Expected:

- Swift parse passes.
- Xcode build succeeds.
- XCTest suite passes.

- [ ] **Step 3: Verify Screen Recording permission behavior**

Run the Atlas app from Xcode:

1. Open the menu bar item.
2. Click `Screenshot` -> `Full`.
3. If macOS prompts for Screen Recording, grant it in System Settings and relaunch the app.
4. Click `Full` again.
5. Expected: editor opens with a real screenshot of the primary display.
6. Click `Area`, select a visible region on the main display, and confirm.
7. Expected: editor opens with real content from the selected region.
8. Click Copy, paste into Preview or another image-capable app.
9. Expected: pasted image contains the real captured image.
10. Draw a pixelate annotation, click Save, open the saved file.
11. Expected: saved file contains the pixelated area, not the unredacted original.

- [ ] **Step 4: Document final verification notes**

Append this section to `docs/superpowers/plans/2026-05-10-uniffi-real-capture.md`:

```markdown
## Execution Verification Notes

- Rust tests:
  - `cargo test -p atlas-core -p atlas-ffi`
  - Result: [fill with pass/fail and failure details]
- Swift/Xcode:
  - `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift`
  - `xcodebuild -project platforms/macos/Atlas.xcodeproj -scheme Atlas -configuration Debug build`
  - `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
  - Result: [fill with pass/fail and failure details]
- Manual capture:
  - Full-screen capture: [fill with observed result]
  - Area capture: [fill with observed result]
  - Copy/save/pin: [fill with observed result]
- Remaining limitation:
  - Capture is still primary-display only because `atlas-core::capture::engine::CaptureEngine` currently uses the first `screenshots::Screen`.
```

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/plans/2026-05-10-uniffi-real-capture.md
git commit -m "docs: record uniffi capture verification"
```

---

## Self-Review

1. **Spec coverage:** The plan covers reproducible UniFFI binding generation, Xcode linking, real capture calls, coordinate mapping, failure reporting, and verification. It explicitly excludes monitoring/port/OCR/translation/multi-display work.
2. **Placeholder scan:** The plan contains exact file paths, concrete code snippets, concrete commands, and expected outcomes. The only human-filled section is the final verification log, which is explicitly an execution record rather than implementation logic.
3. **Type consistency:** `ScreenCapturePixelRegion`, `ScreenCaptureCoordinateMapper`, `AtlasCaptureError`, and `AtlasCaptureService` are defined before use. `AtlasBridge.captureRegion` and `captureFullScreen` are changed consistently from optional-returning mock APIs to throwing live APIs, and `ContentView` is updated accordingly.

---

Plan complete and saved to `docs/superpowers/plans/2026-05-10-uniffi-real-capture.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**

## Execution Verification Notes

- Rust tests:
  - `cargo test -p atlas-core -p atlas-ffi`
  - Result: Passed. `atlas-core` ran 18 tests with 0 failures, `atlas-ffi` ran 4 tests with 0 failures, and `atlas-core` doc-tests ran 0 tests with 0 failures.
- Swift/Xcode:
  - `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift`
  - Result: Passed.
  - `xcodebuild -project platforms/macos/Atlas.xcodeproj -scheme Atlas -configuration Debug build`
  - Result: Passed. Build succeeded; Xcode emitted the standard warning about choosing the first matching macOS destination.
  - `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'`
  - Result: Passed. XCTest ran 20 tests with 0 failures. Xcode emitted the standard destination selection warning and linker warnings about XCTest libraries built for macOS 14.0 while the test target builds for macOS 13.0.
- Manual capture:
  - Full-screen capture: Not performed in this automated run.
  - Area capture: Not performed in this automated run.
  - Copy/save/pin: Not performed in this automated run.
- Remaining limitation:
  - Capture is still primary-display only because `atlas-core::capture::engine::CaptureEngine` currently uses the first `screenshots::Screen`.

# Screenshot Annotation Style v1 Implementation Plan

**Goal:** Let screenshot annotations use selectable colors and line widths while preserving the current default red, 2 px behavior.

**Scope:**
- Add a small Swift model for annotation color choices and clamped line width.
- Add unit tests for metadata, defaults, and line width clamping.
- Wire the screenshot editor toolbar to color swatches and a line width stepper.
- Apply the selected style to rectangle, arrow, pen, and text annotations.

**Out of scope:**
- Freeform text editing.
- Per-tool enablement beyond the existing annotations capability toggle.
- Rust or FFI changes.
- Manual UI verification.

## Tasks

- [x] Task 1: Add failing annotation style model tests.
- [x] Task 2: Implement annotation style model.
- [x] Task 3: Wire style controls into `ScreenshotEditorView`.
- [x] Task 4: Run focused and full macOS unit tests, then record verification notes.

## Verification Notes

Completed on 2026-05-21 in `/tmp/atlas-screenshot-annotation-style-v1`.

- Expected failing test: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotModelsTests` failed before implementation because `ScreenshotAnnotationColor` and `ScreenshotAnnotationStyle` did not exist.
- Swift parse: `swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift` passed with no output.
- Focused tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotModelsTests -only-testing:AtlasTests/ScreenshotEditorRendererTests` passed with 13 tests and 0 failures.
- Full macOS tests: `xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS'` passed with 138 tests and 0 failures.
- Non-blocking environment warnings: Xcode reported CoreSimulator out of date and multiple matching macOS destinations, then used the first macOS destination and completed successfully.

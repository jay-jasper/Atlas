# GIF Recording v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add gated region GIF recording that captures a selected screen region over time, stops on user command, encodes frames into a GIF, and saves/copies the output.

**Architecture:** Keep recording in the macOS layer and isolate live screen access behind protocols. Use the existing region selection UI for choosing a recording rect, a small recorder service for frame timing, ImageIO for GIF encoding, and the existing screenshot output patterns for save/copy. Tests use fake frame sources, fake clocks, and fake encoders so they never require Screen Recording permission.

**Tech Stack:** SwiftUI, AppKit, CoreGraphics, ImageIO, UniformTypeIdentifiers, XCTest, existing Atlas macOS Xcode project.

---

## Scope

This plan implements GIF Recording v1:

- Select a recording region with the existing screenshot selection flow.
- Capture frames on a fixed interval until the user presses Stop.
- Encode captured frames as an animated GIF with a deterministic frame delay.
- Save the GIF to a temporary output file, support copy to pasteboard, and support Save As through `NSSavePanel`.
- Gate the UI through Feature Center screenshot subfeature settings.
- Test frame loop, stop behavior, encoding, and output without requiring live Screen Recording permission.

Out of scope for v1:

- Audio recording.
- Video formats other than GIF.
- Recording whole windows without selecting a region.
- Live Screen Recording permission tests.
- Rust or UniFFI changes.
- Scrolling capture.

## File Structure

- `platforms/macos/Atlas/ScreenshotFeatureSettings.swift`
  - Add `gifRecording` as a screenshot subfeature and expose it through capture capabilities.
- `platforms/macos/Atlas/ScreenshotGIFEncoder.swift`
  - Owns ImageIO GIF encoding from frame images and frame delay.
- `platforms/macos/Atlas/ScreenshotGIFRecording.swift`
  - Owns recording requests, session state, frame source protocol, clock protocol, recorder service, and production adapters.
- `platforms/macos/Atlas/ScreenshotGIFOutput.swift`
  - Owns temporary GIF file writes, pasteboard copy, and Save As output.
- `platforms/macos/Atlas/ScreenshotPanel.swift`
  - Adds the GIF button when capability is enabled.
- `platforms/macos/Atlas/ContentView.swift`
  - Starts region selection, starts/stops recording, shows status, and routes save/copy/open output.
- `platforms/macos/Atlas.xcodeproj/project.pbxproj`
  - Adds new source and test files.
- `platforms/macos/AtlasTests/ScreenshotFeatureSettingsTests.swift`
  - Extends subfeature and capability assertions.
- `platforms/macos/AtlasTests/ScreenshotGIFEncoderTests.swift`
  - Unit tests for animated GIF output metadata.
- `platforms/macos/AtlasTests/ScreenshotGIFRecordingTests.swift`
  - Unit tests for frame loop and stop behavior with fake frames and fake clock.
- `platforms/macos/AtlasTests/ScreenshotGIFOutputTests.swift`
  - Unit tests for file naming, file writes, and pasteboard item construction without writing outside temp directories.

---

### Task 1: Feature Center Gating

**Files:**
- Modify: `platforms/macos/Atlas/ScreenshotFeatureSettings.swift`
- Modify: `platforms/macos/AtlasTests/ScreenshotFeatureSettingsTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [x] **Step 1: Extend feature settings tests for GIF recording**

Add these assertions to `platforms/macos/AtlasTests/ScreenshotFeatureSettingsTests.swift`:

```swift
func testDefaultSettingsEnableGIFRecording() {
    let settings = ScreenshotFeatureSettings.defaultEnabled

    XCTAssertTrue(settings.isEnabled(.gifRecording))
    XCTAssertTrue(settings.captureCapabilities.gifRecording)
}

func testGIFRecordingCanBeDisabled() {
    var settings = ScreenshotFeatureSettings.defaultEnabled
    settings.setEnabled(false, for: .gifRecording)

    XCTAssertFalse(settings.isEnabled(.gifRecording))
    XCTAssertFalse(settings.captureCapabilities.gifRecording)
}
```

Update the stable order expectation in `testFeatureMetadataIsStable()`:

```swift
XCTAssertEqual(ScreenshotSubfeature.allCases.map(\.rawValue), [
    "desktop-capture",
    "window-capture",
    "area-capture",
    "gif-recording",
    "annotations",
    "pinning",
    "ocr",
    "translation",
])
```

- [ ] **Step 2: Run settings tests to verify failure**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotFeatureSettingsTests
```

Expected: FAIL because `ScreenshotSubfeature.gifRecording` and `ScreenshotCaptureCapabilities.gifRecording` do not exist.

- [x] **Step 3: Add GIF recording subfeature**

In `platforms/macos/Atlas/ScreenshotFeatureSettings.swift`, update the affected declarations:

```swift
enum ScreenshotSubfeature: String, CaseIterable, Identifiable {
    case desktopCapture = "desktop-capture"
    case windowCapture = "window-capture"
    case areaCapture = "area-capture"
    case gifRecording = "gif-recording"
    case annotations
    case pinning
    case ocr
    case translation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktopCapture: return "Desktop Capture"
        case .windowCapture: return "Window Capture"
        case .areaCapture: return "Area Capture"
        case .gifRecording: return "GIF Recording"
        case .annotations: return "Annotations"
        case .pinning: return "Pinning"
        case .ocr: return "OCR"
        case .translation: return "Translation"
        }
    }

    var detail: String {
        switch self {
        case .desktopCapture: return "Capture the full desktop."
        case .windowCapture: return "Capture a selected application window."
        case .areaCapture: return "Capture a selected screen region."
        case .gifRecording: return "Record a selected region as an animated GIF."
        case .annotations: return "Show rectangle, arrow, pen, text, and pixelate tools."
        case .pinning: return "Pin screenshots in a floating window."
        case .ocr: return "Recognize text from screenshots."
        case .translation: return "Translate recognized screenshot text."
        }
    }

    var systemImage: String {
        switch self {
        case .desktopCapture: return "display"
        case .windowCapture: return "macwindow"
        case .areaCapture: return "selection.pin.in.out"
        case .gifRecording: return "record.circle"
        case .annotations: return "pencil.and.outline"
        case .pinning: return "pin"
        case .ocr: return "text.viewfinder"
        case .translation: return "globe"
        }
    }
}

struct ScreenshotCaptureCapabilities: Equatable {
    var desktop: Bool
    var window: Bool
    var area: Bool
    var gifRecording: Bool

    static let allEnabled = ScreenshotCaptureCapabilities(
        desktop: true,
        window: true,
        area: true,
        gifRecording: true
    )
}
```

Update `ScreenshotFeatureSettings.captureCapabilities`:

```swift
var captureCapabilities: ScreenshotCaptureCapabilities {
    ScreenshotCaptureCapabilities(
        desktop: isEnabled(.desktopCapture),
        window: isEnabled(.windowCapture),
        area: isEnabled(.areaCapture),
        gifRecording: isEnabled(.gifRecording)
    )
}
```

- [x] **Step 4: Run settings tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotFeatureSettingsTests -only-testing:AtlasTests/ScreenshotFeatureSettingsPanelTests
```

Expected: PASS.

- [ ] **Step 5: Commit feature gating model**

Run:

```bash
git add platforms/macos/Atlas/ScreenshotFeatureSettings.swift platforms/macos/AtlasTests/ScreenshotFeatureSettingsTests.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat: gate gif recording"
```

Expected: Commit succeeds with only settings/test/project updates.

---

### Task 2: GIF Encoder

**Files:**
- Create: `platforms/macos/Atlas/ScreenshotGIFEncoder.swift`
- Create: `platforms/macos/AtlasTests/ScreenshotGIFEncoderTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [x] **Step 1: Write encoder tests**

Create `platforms/macos/AtlasTests/ScreenshotGIFEncoderTests.swift`:

```swift
import AppKit
import ImageIO
import XCTest
@testable import Atlas

final class ScreenshotGIFEncoderTests: XCTestCase {
    func testEncodesAnimatedGIFWithFrameCount() throws {
        let frames = [
            ScreenshotGIFFrame(image: try image(width: 6, height: 4, color: .red), delay: 0.2),
            ScreenshotGIFFrame(image: try image(width: 6, height: 4, color: .blue), delay: 0.2),
        ]

        let data = try ImageIOScreenshotGIFEncoder().encode(frames: frames, loopCount: 0)

        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "com.compuserve.gif")
        XCTAssertEqual(CGImageSourceGetCount(source), 2)
    }

    func testRejectsEmptyFrames() {
        XCTAssertThrowsError(try ImageIOScreenshotGIFEncoder().encode(frames: [], loopCount: 0)) { error in
            XCTAssertEqual(error as? ScreenshotGIFEncodingError, .emptyFrames)
        }
    }

    private func image(width: Int, height: Int, color: NSColor) throws -> CGImage {
        let nsImage = NSImage(size: NSSize(width: width, height: height))
        nsImage.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        nsImage.unlockFocus()
        return try XCTUnwrap(nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }
}
```

- [ ] **Step 2: Run encoder tests to verify failure**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotGIFEncoderTests
```

Expected: FAIL because GIF encoder types do not exist or the test file is not in the project.

- [x] **Step 3: Add ImageIO GIF encoder**

Create `platforms/macos/Atlas/ScreenshotGIFEncoder.swift`:

```swift
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ScreenshotGIFFrame: Equatable {
    let image: CGImage
    let delay: TimeInterval
}

enum ScreenshotGIFEncodingError: LocalizedError, Equatable {
    case emptyFrames
    case destinationCreationFailed
    case finalizeFailed

    var errorDescription: String? {
        switch self {
        case .emptyFrames: return "GIF recording did not capture any frames"
        case .destinationCreationFailed: return "GIF encoder could not create an output destination"
        case .finalizeFailed: return "GIF encoder could not finish the output file"
        }
    }
}

protocol ScreenshotGIFEncoding {
    func encode(frames: [ScreenshotGIFFrame], loopCount: Int) throws -> Data
}

struct ImageIOScreenshotGIFEncoder: ScreenshotGIFEncoding {
    func encode(frames: [ScreenshotGIFFrame], loopCount: Int = 0) throws -> Data {
        guard !frames.isEmpty else {
            throw ScreenshotGIFEncodingError.emptyFrames
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            throw ScreenshotGIFEncodingError.destinationCreationFailed
        }

        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: loopCount
            ]
        ] as CFDictionary)

        for frame in frames {
            CGImageDestinationAddImage(destination, frame.image, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: frame.delay
                ]
            ] as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotGIFEncodingError.finalizeFailed
        }

        return data as Data
    }
}
```

- [x] **Step 4: Add files to Xcode project**

Add:

- `ScreenshotGIFEncoder.swift` to the `Atlas` target Sources.
- `ScreenshotGIFEncoderTests.swift` to the `AtlasTests` target Sources.

- [x] **Step 5: Run encoder tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotGIFEncoderTests
```

Expected: PASS with 2 tests.

- [ ] **Step 6: Commit encoder**

Run:

```bash
git add platforms/macos/Atlas/ScreenshotGIFEncoder.swift platforms/macos/AtlasTests/ScreenshotGIFEncoderTests.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat: encode screenshot gif recordings"
```

Expected: Commit succeeds.

---

### Task 3: Recorder Service and Stop Control

**Files:**
- Create: `platforms/macos/Atlas/ScreenshotGIFRecording.swift`
- Create: `platforms/macos/AtlasTests/ScreenshotGIFRecordingTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write recorder tests**

Create `platforms/macos/AtlasTests/ScreenshotGIFRecordingTests.swift`:

```swift
import AppKit
import XCTest
@testable import Atlas

final class ScreenshotGIFRecordingTests: XCTestCase {
    func testRecorderCapturesUntilStopRequested() throws {
        let frameSource = StubGIFFrameSource(frame: try image(width: 4, height: 4, color: .red))
        let clock = StubGIFClock(stopAfterSleeps: 2)
        let encoder = StubGIFEncoder(output: Data([0x47, 0x49, 0x46]))
        let recorder = ScreenshotGIFRecorder(
            permissionProvider: StubGIFPermissionProvider(screenRecordingAllowed: true),
            frameSource: frameSource,
            clock: clock,
            encoder: encoder
        )

        let result = try recorder.record(
            request: ScreenshotGIFRecordingRequest(
                region: CGRect(x: 10, y: 20, width: 30, height: 40),
                frameDelay: 0.1,
                maximumFrames: 10
            ),
            shouldStop: { clock.shouldStop }
        )

        XCTAssertEqual(frameSource.regions, [
            CGRect(x: 10, y: 20, width: 30, height: 40),
            CGRect(x: 10, y: 20, width: 30, height: 40),
            CGRect(x: 10, y: 20, width: 30, height: 40),
        ])
        XCTAssertEqual(clock.sleepDurations, [0.1, 0.1])
        XCTAssertEqual(encoder.receivedFrames.count, 3)
        XCTAssertEqual(result.frameCount, 3)
        XCTAssertEqual(result.gifData, Data([0x47, 0x49, 0x46]))
    }

    func testRecorderStopsAtMaximumFrames() throws {
        let frameSource = StubGIFFrameSource(frame: try image(width: 4, height: 4, color: .blue))
        let recorder = ScreenshotGIFRecorder(
            permissionProvider: StubGIFPermissionProvider(screenRecordingAllowed: true),
            frameSource: frameSource,
            clock: StubGIFClock(stopAfterSleeps: 99),
            encoder: StubGIFEncoder(output: Data([1]))
        )

        let result = try recorder.record(
            request: ScreenshotGIFRecordingRequest(
                region: CGRect(x: 0, y: 0, width: 16, height: 16),
                frameDelay: 0.05,
                maximumFrames: 2
            ),
            shouldStop: { false }
        )

        XCTAssertEqual(result.frameCount, 2)
    }

    func testRecorderRejectsMissingScreenRecordingPermission() {
        let recorder = ScreenshotGIFRecorder(
            permissionProvider: StubGIFPermissionProvider(screenRecordingAllowed: false),
            frameSource: StubGIFFrameSource(frame: CGImage.emptyTestImage),
            clock: StubGIFClock(stopAfterSleeps: 1),
            encoder: StubGIFEncoder(output: Data())
        )

        XCTAssertThrowsError(
            try recorder.record(
                request: ScreenshotGIFRecordingRequest(region: .zero, frameDelay: 0.1, maximumFrames: 1),
                shouldStop: { false }
            )
        ) { error in
            XCTAssertEqual(error as? ScreenshotGIFRecordingError, .screenRecordingPermissionMissing)
        }
    }

    private func image(width: Int, height: Int, color: NSColor) throws -> CGImage {
        let nsImage = NSImage(size: NSSize(width: width, height: height))
        nsImage.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        nsImage.unlockFocus()
        return try XCTUnwrap(nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }
}

private final class StubGIFFrameSource: ScreenshotGIFFrameCapturing {
    let frame: CGImage
    private(set) var regions: [CGRect] = []

    init(frame: CGImage) {
        self.frame = frame
    }

    func captureFrame(in region: CGRect) throws -> CGImage {
        regions.append(region)
        return frame
    }
}

private final class StubGIFClock: ScreenshotGIFClocking {
    let stopAfterSleeps: Int
    private(set) var sleepDurations: [TimeInterval] = []

    init(stopAfterSleeps: Int) {
        self.stopAfterSleeps = stopAfterSleeps
    }

    var shouldStop: Bool {
        sleepDurations.count >= stopAfterSleeps
    }

    func sleep(for duration: TimeInterval) {
        sleepDurations.append(duration)
    }
}

private final class StubGIFEncoder: ScreenshotGIFEncoding {
    let output: Data
    private(set) var receivedFrames: [ScreenshotGIFFrame] = []

    init(output: Data) {
        self.output = output
    }

    func encode(frames: [ScreenshotGIFFrame], loopCount: Int) throws -> Data {
        receivedFrames = frames
        return output
    }
}

private struct StubGIFPermissionProvider: ScreenshotGIFRecordingPermissionProviding {
    let screenRecordingAllowed: Bool
}

private extension CGImage {
    static var emptyTestImage: CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
```

- [ ] **Step 2: Run recorder tests to verify failure**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotGIFRecordingTests
```

Expected: FAIL because recorder types do not exist or the test file is not in the project.

- [ ] **Step 3: Add recorder implementation**

Create `platforms/macos/Atlas/ScreenshotGIFRecording.swift`:

```swift
import AppKit
import CoreGraphics

struct ScreenshotGIFRecordingRequest: Equatable {
    let region: CGRect
    let frameDelay: TimeInterval
    let maximumFrames: Int
}

struct ScreenshotGIFRecordingResult: Equatable {
    let gifData: Data
    let frameCount: Int
    let region: CGRect
}

final class ScreenshotGIFRecordingSession {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

enum ScreenshotGIFRecordingError: LocalizedError, Equatable {
    case screenRecordingPermissionMissing
    case noFramesCaptured
    case invalidFrameRegion

    var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionMissing:
            return "Screen Recording permission is required for GIF recording"
        case .noFramesCaptured:
            return "GIF recording did not capture any frames"
        case .invalidFrameRegion:
            return "GIF recording region is invalid"
        }
    }
}

protocol ScreenshotGIFRecordingPermissionProviding {
    var screenRecordingAllowed: Bool { get }
}

struct LiveScreenshotGIFRecordingPermissionProvider: ScreenshotGIFRecordingPermissionProviding {
    var screenRecordingAllowed: Bool {
        CGPreflightScreenCaptureAccess()
    }
}

protocol ScreenshotGIFFrameCapturing {
    func captureFrame(in region: CGRect) throws -> CGImage
}

struct CGScreenshotGIFFrameCapture: ScreenshotGIFFrameCapturing {
    func captureFrame(in region: CGRect) throws -> CGImage {
        guard region.width > 0, region.height > 0 else {
            throw ScreenshotGIFRecordingError.invalidFrameRegion
        }
        guard let image = CGWindowListCreateImage(region, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]) else {
            throw ScreenshotGIFRecordingError.noFramesCaptured
        }
        return image
    }
}

protocol ScreenshotGIFClocking {
    func sleep(for duration: TimeInterval)
}

struct ThreadScreenshotGIFClock: ScreenshotGIFClocking {
    func sleep(for duration: TimeInterval) {
        Thread.sleep(forTimeInterval: duration)
    }
}

struct ScreenshotGIFRecorder {
    let permissionProvider: ScreenshotGIFRecordingPermissionProviding
    let frameSource: ScreenshotGIFFrameCapturing
    let clock: ScreenshotGIFClocking
    let encoder: ScreenshotGIFEncoding

    init(
        permissionProvider: ScreenshotGIFRecordingPermissionProviding = LiveScreenshotGIFRecordingPermissionProvider(),
        frameSource: ScreenshotGIFFrameCapturing = CGScreenshotGIFFrameCapture(),
        clock: ScreenshotGIFClocking = ThreadScreenshotGIFClock(),
        encoder: ScreenshotGIFEncoding = ImageIOScreenshotGIFEncoder()
    ) {
        self.permissionProvider = permissionProvider
        self.frameSource = frameSource
        self.clock = clock
        self.encoder = encoder
    }

    func record(
        request: ScreenshotGIFRecordingRequest,
        shouldStop: () -> Bool
    ) throws -> ScreenshotGIFRecordingResult {
        guard permissionProvider.screenRecordingAllowed else {
            throw ScreenshotGIFRecordingError.screenRecordingPermissionMissing
        }
        guard request.region.width > 0, request.region.height > 0 else {
            throw ScreenshotGIFRecordingError.invalidFrameRegion
        }

        var frames: [ScreenshotGIFFrame] = []
        let maximumFrames = max(1, request.maximumFrames)
        let delay = max(0.03, request.frameDelay)

        while frames.count < maximumFrames {
            frames.append(
                ScreenshotGIFFrame(
                    image: try frameSource.captureFrame(in: request.region),
                    delay: delay
                )
            )
            if shouldStop() { break }
            if frames.count < maximumFrames {
                clock.sleep(for: delay)
            }
        }

        guard !frames.isEmpty else {
            throw ScreenshotGIFRecordingError.noFramesCaptured
        }

        return ScreenshotGIFRecordingResult(
            gifData: try encoder.encode(frames: frames, loopCount: 0),
            frameCount: frames.count,
            region: request.region
        )
    }
}
```

- [ ] **Step 4: Add files to Xcode project**

Add:

- `ScreenshotGIFRecording.swift` to the `Atlas` target Sources.
- `ScreenshotGIFRecordingTests.swift` to the `AtlasTests` target Sources.

- [ ] **Step 5: Run recorder tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotGIFRecordingTests
```

Expected: PASS with 3 tests.

- [ ] **Step 6: Commit recorder**

Run:

```bash
git add platforms/macos/Atlas/ScreenshotGIFRecording.swift platforms/macos/AtlasTests/ScreenshotGIFRecordingTests.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat: record selected regions as gif"
```

Expected: Commit succeeds.

---

### Task 4: GIF Output Save and Copy

**Files:**
- Create: `platforms/macos/Atlas/ScreenshotGIFOutput.swift`
- Create: `platforms/macos/AtlasTests/ScreenshotGIFOutputTests.swift`
- Modify: `platforms/macos/Atlas.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write output tests**

Create `platforms/macos/AtlasTests/ScreenshotGIFOutputTests.swift`:

```swift
import AppKit
import XCTest
@testable import Atlas

final class ScreenshotGIFOutputTests: XCTestCase {
    func testWritesTemporaryGIFFileWithStableExtension() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GIFOutputTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = ScreenshotGIFOutputStore(rootDirectory: root)

        let item = try output.writeTemporaryGIF(Data([1, 2, 3]), date: Date(timeIntervalSince1970: 1_704_067_200))

        XCTAssertTrue(item.url.lastPathComponent.hasSuffix(".gif"))
        XCTAssertEqual(try Data(contentsOf: item.url), Data([1, 2, 3]))
        XCTAssertEqual(item.filename, "Atlas-GIF-20240101-000000.gif")
    }

    func testPasteboardItemContainsFileURL() throws {
        let url = URL(fileURLWithPath: "/tmp/Atlas-GIF-test.gif")
        let item = ScreenshotGIFOutputItem(url: url, filename: "Atlas-GIF-test.gif")

        let pasteboardItem = ScreenshotGIFPasteboardWriter.pasteboardItem(for: item)

        XCTAssertEqual(pasteboardItem.string(forType: .fileURL), url.absoluteString)
    }
}
```

- [ ] **Step 2: Run output tests to verify failure**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotGIFOutputTests
```

Expected: FAIL because GIF output types do not exist or the test file is not in the project.

- [ ] **Step 3: Add output implementation**

Create `platforms/macos/Atlas/ScreenshotGIFOutput.swift`:

```swift
import AppKit
import Foundation

struct ScreenshotGIFOutputItem: Equatable {
    let url: URL
    let filename: String
}

struct ScreenshotGIFOutputStore {
    private let rootDirectory: URL
    private let fileManager: FileManager

    init(
        rootDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("Atlas GIF Recordings", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    func writeTemporaryGIF(_ data: Data, date: Date = Date()) throws -> ScreenshotGIFOutputItem {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let filename = Self.filename(for: date)
        let url = rootDirectory.appendingPathComponent(filename, isDirectory: false)
        try data.write(to: url, options: .atomic)
        return ScreenshotGIFOutputItem(url: url, filename: filename)
    }

    static func filename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "Atlas-GIF-\(formatter.string(from: date)).gif"
    }
}

enum ScreenshotGIFPasteboardWriter {
    static func pasteboardItem(for item: ScreenshotGIFOutputItem) -> NSPasteboardItem {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(item.url.absoluteString, forType: .fileURL)
        return pasteboardItem
    }

    static func copy(_ item: ScreenshotGIFOutputItem, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.writeObjects([item.url as NSURL])
    }
}
```

- [ ] **Step 4: Add files to Xcode project**

Add:

- `ScreenshotGIFOutput.swift` to the `Atlas` target Sources.
- `ScreenshotGIFOutputTests.swift` to the `AtlasTests` target Sources.

- [ ] **Step 5: Run output tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotGIFOutputTests
```

Expected: PASS with 2 tests.

- [ ] **Step 6: Commit output helpers**

Run:

```bash
git add platforms/macos/Atlas/ScreenshotGIFOutput.swift platforms/macos/AtlasTests/ScreenshotGIFOutputTests.swift platforms/macos/Atlas.xcodeproj/project.pbxproj
git commit -m "feat: add gif recording output helpers"
```

Expected: Commit succeeds.

---

### Task 5: Region Selection and UI Wiring

**Files:**
- Modify: `platforms/macos/Atlas/ScreenshotPanel.swift`
- Modify: `platforms/macos/Atlas/ContentView.swift`

- [ ] **Step 1: Add the GIF button to the screenshot panel**

Update `ScreenshotPanel` with the new callback and button:

```swift
struct ScreenshotPanel: View {
    let capabilities: ScreenshotCaptureCapabilities
    let onCaptureDesktop: () -> Void
    let onCaptureWindow: () -> Void
    let onCaptureArea: () -> Void
    let onRecordGIF: () -> Void

    var body: some View {
        Group {
            Text("Screenshot").font(.subheadline).foregroundColor(.secondary)
            HStack {
                if capabilities.desktop {
                    captureButton(for: .desktop, action: onCaptureDesktop, prominent: true)
                }
                if capabilities.window {
                    captureButton(for: .window, action: onCaptureWindow, prominent: !capabilities.desktop)
                }
                if capabilities.area {
                    captureButton(for: .area, action: onCaptureArea, prominent: !capabilities.desktop && !capabilities.window)
                }
                if capabilities.gifRecording {
                    Button(action: onRecordGIF) {
                        Label("GIF", systemImage: "record.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}
```

Compatibility note: this `ScreenshotPanel` change is additive. If `docs/superpowers/plans/2026-05-22-scrolling-capture-v1.md` has already been applied, keep its `onCaptureScrolling` callback and Scrolling button when adding `onRecordGIF`. If both advanced screenshot plans are applied, the final panel shape must include both advanced callbacks:

```swift
struct ScreenshotPanel: View {
    let capabilities: ScreenshotCaptureCapabilities
    let onCaptureDesktop: () -> Void
    let onCaptureWindow: () -> Void
    let onCaptureArea: () -> Void
    let onCaptureScrolling: () -> Void
    let onRecordGIF: () -> Void

    var body: some View {
        Group {
            Text("Screenshot").font(.subheadline).foregroundColor(.secondary)
            HStack {
                if capabilities.desktop {
                    captureButton(for: .desktop, action: onCaptureDesktop, prominent: true)
                }
                if capabilities.window {
                    captureButton(for: .window, action: onCaptureWindow, prominent: !capabilities.desktop)
                }
                if capabilities.area {
                    captureButton(for: .area, action: onCaptureArea, prominent: !capabilities.desktop && !capabilities.window)
                }
                if capabilities.scrolling {
                    Button(action: onCaptureScrolling) {
                        Label("Scrolling", systemImage: "rectangle.stack.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }
                if capabilities.gifRecording {
                    Button(action: onRecordGIF) {
                        Label("GIF", systemImage: "record.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Add recording state and output routing to `ContentView`**

In `platforms/macos/Atlas/ContentView.swift`, add these properties:

```swift
@State private var isRecordingGIF = false
@State private var lastGIFOutput: ScreenshotGIFOutputItem?
@State private var gifRecordingSession: ScreenshotGIFRecordingSession?

private let gifRecorder = ScreenshotGIFRecorder()
private let gifOutputStore = ScreenshotGIFOutputStore()
```

Update every `ScreenshotPanel(...)` call to pass:

```swift
onRecordGIF: startGIFRegionSelection
```

Add this compact control near the existing screenshot status/output controls:

```swift
if isRecordingGIF {
    HStack {
        Label("Recording GIF", systemImage: "record.circle")
        Spacer()
        Button("Stop") {
            gifRecordingSession?.cancel()
        }
        .buttonStyle(.borderedProminent)
    }
}

if let lastGIFOutput, !isRecordingGIF {
    HStack {
        Label(lastGIFOutput.filename, systemImage: "photo.stack")
            .lineLimit(1)
        Spacer()
        Button("Copy GIF", action: copyLastGIFRecording)
            .buttonStyle(.bordered)
        Button("Save As", action: saveLastGIFRecording)
            .buttonStyle(.borderedProminent)
    }
}
```

Add these helpers near the existing area capture helpers:

```swift
private func startGIFRegionSelection() {
    guard screenshotFeatureSettings.captureCapabilities.gifRecording else {
        showStatus("GIF recording is disabled", kind: .error)
        return
    }

    startRegionSelection(onSelect: { region in
        startGIFRecording(in: region)
    })
}

private func startGIFRecording(in region: CGRect) {
    let session = ScreenshotGIFRecordingSession()
    gifRecordingSession = session
    isRecordingGIF = true

    DispatchQueue.global(qos: .userInitiated).async {
        do {
            let result = try gifRecorder.record(
                request: ScreenshotGIFRecordingRequest(
                    region: region,
                    frameDelay: 0.12,
                    maximumFrames: 600
                ),
                shouldStop: { session.isCancelled }
            )
            let output = try gifOutputStore.writeTemporaryGIF(result.gifData)

            DispatchQueue.main.async {
                lastGIFOutput = output
                isRecordingGIF = false
                gifRecordingSession = nil
                showStatus("Saved GIF recording")
            }
        } catch {
            DispatchQueue.main.async {
                isRecordingGIF = false
                gifRecordingSession = nil
                showStatus(error.localizedDescription, kind: .error)
            }
        }
    }
}

private func copyLastGIFRecording() {
    guard let lastGIFOutput else {
        showStatus("No GIF recording to copy", kind: .error)
        return
    }
    ScreenshotGIFPasteboardWriter.copy(lastGIFOutput)
    showStatus("Copied GIF recording")
}

private func saveLastGIFRecording() {
    guard let lastGIFOutput else {
        showStatus("No GIF recording to save", kind: .error)
        return
    }

    let panel = NSSavePanel()
    panel.nameFieldStringValue = lastGIFOutput.filename
    panel.allowedContentTypes = [.gif]
    guard panel.runModal() == .OK, let destination = panel.url else { return }

    do {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: lastGIFOutput.url, to: destination)
        showStatus("Saved GIF recording")
    } catch {
        showStatus(error.localizedDescription, kind: .error)
    }
}
```

Replace the existing `showSelectionWindow()` body with this small delegation, then add the reusable static-presenter helper below it:

```swift
private func showSelectionWindow() {
    guard screenshotFeatureSettings.captureCapabilities.area else {
        showStatus("Area capture is disabled", kind: .error)
        return
    }

    startRegionSelection(onSelect: captureSelection)
}

private func startRegionSelection(onSelect: @escaping (CGRect) -> Void) {
    let previewImageData = selectionPreviewImageData()
    ScreenshotSelectionWindow.show(
        previewImageData: previewImageData,
        onCancel: {},
        onCapture: onSelect
    )
}
```

- [ ] **Step 3: Parse Swift files**

Run:

```bash
swiftc -parse platforms/macos/Atlas/*.swift platforms/macos/Generated/AtlasFFI/atlas.swift
```

Expected: PASS with no output.

- [ ] **Step 4: Run focused GIF tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotFeatureSettingsTests -only-testing:AtlasTests/ScreenshotGIFEncoderTests -only-testing:AtlasTests/ScreenshotGIFRecordingTests -only-testing:AtlasTests/ScreenshotGIFOutputTests
```

Expected: PASS.

- [ ] **Step 5: Commit UI wiring**

Run:

```bash
git add platforms/macos/Atlas/ScreenshotPanel.swift platforms/macos/Atlas/ContentView.swift
git commit -m "feat: wire gif recording controls"
```

Expected: Commit succeeds.

---

### Task 6: Final Verification

**Files:**
- Read: all files modified by this plan.

- [ ] **Step 1: Run screenshot and GIF tests**

Run:

```bash
xcodebuild test -project platforms/macos/Atlas.xcodeproj -scheme Atlas -destination 'platform=macOS' -only-testing:AtlasTests/ScreenshotCaptureModeTests -only-testing:AtlasTests/AtlasCaptureServiceTests -only-testing:AtlasTests/ScreenshotFeatureSettingsTests -only-testing:AtlasTests/ScreenshotFeatureSettingsPanelTests -only-testing:AtlasTests/ScreenshotGIFEncoderTests -only-testing:AtlasTests/ScreenshotGIFRecordingTests -only-testing:AtlasTests/ScreenshotGIFOutputTests
```

Expected: PASS.

- [ ] **Step 2: Verify tests do not require live Screen Recording permission**

Run:

```bash
rg -n 'CGPreflightScreenCaptureAccess|CGRequestScreenCaptureAccess|CGWindowListCreateImage|AXIsProcessTrusted' platforms/macos/AtlasTests
```

Expected: no output. Production files may reference these APIs, but tests must use fakes.

- [ ] **Step 3: Verify no Rust changes are needed**

Run:

```bash
git diff -- crates/atlas-core crates/atlas-ffi
```

Expected: no output.

- [ ] **Step 4: Commit final plan note if this plan file is updated**

Run:

```bash
git add docs/superpowers/plans/2026-05-22-gif-recording-v1.md
git commit -m "docs: record gif recording verification"
```

Expected: Commit succeeds only if verification notes were added to this plan.

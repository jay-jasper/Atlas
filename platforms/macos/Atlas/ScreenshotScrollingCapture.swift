import AppKit
import ApplicationServices
import CoreGraphics

struct ScrollingCaptureRequest: Equatable {
    let window: CapturableWindow
    let maxFrames: Int
    let scrollDelta: Int32
    let overlapPixels: Int
}

struct ScrollingCaptureResult: Equatable {
    let pngData: Data
    let framesCaptured: Int
    let libraryItem: ScreenshotLibraryItem
}

enum ScrollingCaptureError: LocalizedError, Equatable {
    case screenRecordingPermissionMissing
    case accessibilityPermissionMissing
    case noFramesCaptured

    var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionMissing:
            return "Screen Recording permission is required for scrolling capture"
        case .accessibilityPermissionMissing:
            return "Accessibility permission is required to scroll the selected window"
        case .noFramesCaptured:
            return "Scrolling capture did not capture any frames"
        }
    }
}

protocol ScrollingCapturePermissionProviding {
    var screenRecordingAllowed: Bool { get }
    var accessibilityAllowed: Bool { get }
}

struct LiveScrollingCapturePermissions: ScrollingCapturePermissionProviding {
    var screenRecordingAllowed: Bool {
        CGPreflightScreenCaptureAccess()
    }

    var accessibilityAllowed: Bool {
        AXIsProcessTrusted()
    }
}

protocol ScrollingWindowFrameCapturing {
    func captureWindowFrame(id: CGWindowID) throws -> Data
}

struct AtlasScrollingWindowFrameCapture: ScrollingWindowFrameCapturing {
    func captureWindowFrame(id: CGWindowID) throws -> Data {
        try AtlasBridge.captureWindow(id: id)
    }
}

protocol WindowScrollEventSending {
    func scrollWindow(id: CGWindowID, deltaY: Int32) throws
}

struct CGWindowScrollEventSender: WindowScrollEventSending {
    func scrollWindow(id: CGWindowID, deltaY: Int32) throws {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: deltaY,
            wheel2: 0,
            wheel3: 0
        ) else {
            return
        }

        event.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.12)
    }
}

struct ScreenshotScrollingCaptureService {
    let permissions: ScrollingCapturePermissionProviding
    let frameCapture: ScrollingWindowFrameCapturing
    let scrollSender: WindowScrollEventSending
    let stitcher: ScreenshotImageStitching
    let libraryStore: ScreenshotLibraryStore

    init(
        permissions: ScrollingCapturePermissionProviding = LiveScrollingCapturePermissions(),
        frameCapture: ScrollingWindowFrameCapturing = AtlasScrollingWindowFrameCapture(),
        scrollSender: WindowScrollEventSending = CGWindowScrollEventSender(),
        stitcher: ScreenshotImageStitching = VerticalScreenshotImageStitcher(),
        libraryStore: ScreenshotLibraryStore = ScreenshotLibraryStore()
    ) {
        self.permissions = permissions
        self.frameCapture = frameCapture
        self.scrollSender = scrollSender
        self.stitcher = stitcher
        self.libraryStore = libraryStore
    }

    func capture(request: ScrollingCaptureRequest) throws -> ScrollingCaptureResult {
        guard permissions.screenRecordingAllowed else {
            throw ScrollingCaptureError.screenRecordingPermissionMissing
        }
        guard permissions.accessibilityAllowed else {
            throw ScrollingCaptureError.accessibilityPermissionMissing
        }

        let maxFrames = max(1, request.maxFrames)
        var frames: [Data] = []

        for index in 0..<maxFrames {
            frames.append(try frameCapture.captureWindowFrame(id: request.window.id))
            if index < maxFrames - 1 {
                try scrollSender.scrollWindow(id: request.window.id, deltaY: request.scrollDelta)
            }
        }

        guard !frames.isEmpty else {
            throw ScrollingCaptureError.noFramesCaptured
        }

        let output = try stitcher.stitch(frames: frames, overlapPixels: request.overlapPixels)
        let dimensions = NSImage(data: output)?.size ?? request.window.bounds.size
        let item = try libraryStore.addScreenshot(
            pngData: output,
            pixelWidth: Int(dimensions.width.rounded()),
            pixelHeight: Int(dimensions.height.rounded()),
            source: "Scrolling Window: \(request.window.ownerName) - \(request.window.title)"
        )

        return ScrollingCaptureResult(
            pngData: output,
            framesCaptured: frames.count,
            libraryItem: item
        )
    }
}

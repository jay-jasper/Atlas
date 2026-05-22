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
        guard let image = CGWindowListCreateImage(
            region,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
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

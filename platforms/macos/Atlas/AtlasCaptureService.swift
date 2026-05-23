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

    init(
        captureFullScreen: @escaping () throws -> Data,
        captureRegion: @escaping (Int32, Int32, UInt32, UInt32) throws -> Data,
        accessLogger: PrivacyPulseAccessLogging = NoopPrivacyPulseAccessLogger()
    ) {
        self.captureFullScreen = {
            accessLogger.record(
                category: .screenRecording,
                title: "Screen Capture",
                detail: "Atlas requested full screen pixels for capture"
            )
            return try captureFullScreen()
        }
        self.captureRegion = { x, y, width, height in
            accessLogger.record(
                category: .screenRecording,
                title: "Screen Capture",
                detail: "Atlas requested region pixels for capture"
            )
            return try captureRegion(x, y, width, height)
        }
    }

    func captureRegion(_ region: ScreenCapturePixelRegion) throws -> Data {
        try captureRegion(region.x, region.y, region.width, region.height)
    }

    static func logging(base: AtlasCaptureService, accessLogger: PrivacyPulseAccessLogging) -> AtlasCaptureService {
        AtlasCaptureService(
            captureFullScreen: base.captureFullScreen,
            captureRegion: base.captureRegion,
            accessLogger: accessLogger
        )
    }
}

extension AtlasCaptureService {
    static let live = AtlasCaptureService(
        captureFullScreen: {
            do {
                return Data(try Atlas.captureFullScreen())
            } catch {
                throw AtlasCaptureError.captureFailed(error.localizedDescription)
            }
        },
        captureRegion: { x, y, width, height in
            do {
                return Data(try Atlas.captureRegion(x: x, y: y, width: width, height: height))
            } catch {
                throw AtlasCaptureError.captureFailed(error.localizedDescription)
            }
        }
    )
}

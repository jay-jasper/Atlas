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

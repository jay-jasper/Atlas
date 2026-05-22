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
        case .emptyFrames:
            return "GIF recording did not capture any frames"
        case .destinationCreationFailed:
            return "GIF encoder could not create an output destination"
        case .finalizeFailed:
            return "GIF encoder could not finish the output file"
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

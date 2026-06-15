import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

@MainActor
final class GIFProcessingService: ObservableObject {
    @Published var scale: Double = 1.0
    @Published var maxDimension: Double = 0 // 0 = no cap
    @Published private(set) var statusMessage = ""
    @Published private(set) var lastOutputSize: CGSize?

    /// Re-encodes a GIF at `url` applying the configured scale / max dimension,
    /// writing a `-processed.gif` next to it. Returns the output URL on success.
    @discardableResult
    func process(url: URL) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(source) == UTType.gif.identifier as CFString else {
            statusMessage = "Not a GIF file."
            return nil
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { statusMessage = "Empty GIF."; return nil }

        let outURL = url.deletingPathExtension().appendingPathExtension("processed.gif")
        guard let dest = CGImageDestinationCreateWithURL(
            outURL as CFURL, UTType.gif.identifier as CFString, frameCount, nil
        ) else { statusMessage = "Could not create output."; return nil }

        CGImageDestinationSetProperties(dest, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)

        var outSize: CGSize?
        for index in 0..<frameCount {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let target = targetSize(for: CGSize(width: frame.width, height: frame.height))
            outSize = target
            let resized = resize(frame, to: target) ?? frame
            let delay = frameDelay(source: source, index: index)
            CGImageDestinationAddImage(dest, resized, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]
            ] as CFDictionary)
        }

        guard CGImageDestinationFinalize(dest) else {
            statusMessage = "Encoding failed."
            return nil
        }
        lastOutputSize = outSize
        statusMessage = "Saved \(outURL.lastPathComponent)."
        return outURL
    }

    func targetSize(for source: CGSize) -> CGSize {
        var size = GIFResize.scaled(source, by: scale)
        if maxDimension > 0 {
            size = GIFResize.fitted(size, maxDimension: CGFloat(maxDimension))
        }
        return size
    }

    private func frameDelay(source: CGImageSource, index: Int) -> Double {
        let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        return (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
    }

    private func resize(_ image: CGImage, to size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

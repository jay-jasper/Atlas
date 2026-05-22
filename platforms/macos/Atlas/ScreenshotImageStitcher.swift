import AppKit

enum ScreenshotImageStitchingError: LocalizedError, Equatable {
    case emptyFrames
    case invalidFrame
    case outputEncodingFailed

    var errorDescription: String? {
        switch self {
        case .emptyFrames:
            return "Scrolling capture did not produce any frames"
        case .invalidFrame:
            return "Scrolling capture produced an invalid image frame"
        case .outputEncodingFailed:
            return "Scrolling capture could not encode the stitched PNG"
        }
    }
}

protocol ScreenshotImageStitching {
    func stitch(frames: [Data], overlapPixels: Int) throws -> Data
}

struct VerticalScreenshotImageStitcher: ScreenshotImageStitching {
    func stitch(frames: [Data], overlapPixels: Int) throws -> Data {
        guard !frames.isEmpty else {
            throw ScreenshotImageStitchingError.emptyFrames
        }

        let images = try frames.map { data -> NSImage in
            guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
                throw ScreenshotImageStitchingError.invalidFrame
            }
            return image
        }

        let width = images.map(\.size.width).max() ?? 0
        let trimmedOverlap = max(0, overlapPixels)
        let height = images.enumerated().reduce(CGFloat(0)) { total, entry in
            let trim = entry.offset == 0 ? 0 : min(trimmedOverlap, Int(entry.element.size.height))
            return total + entry.element.size.height - CGFloat(trim)
        }

        let output = NSImage(size: NSSize(width: width, height: height))
        output.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: output.size).fill()

        var y = height
        for (index, image) in images.enumerated() {
            let cropTop = CGFloat(index == 0 ? 0 : min(trimmedOverlap, Int(image.size.height)))
            let drawHeight = image.size.height - cropTop
            y -= drawHeight
            image.draw(
                in: NSRect(x: 0, y: y, width: image.size.width, height: drawHeight),
                from: NSRect(x: 0, y: 0, width: image.size.width, height: drawHeight),
                operation: .copy,
                fraction: 1
            )
        }
        output.unlockFocus()

        guard
            let tiff = output.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw ScreenshotImageStitchingError.outputEncodingFailed
        }

        return png
    }
}

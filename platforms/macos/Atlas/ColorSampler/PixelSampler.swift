import CoreGraphics
import Foundation

/// Samples pixel colors from a CGImage (e.g. a paused video frame). The
/// extraction is deterministic and testable with a constructed image.
enum PixelSampler {
    /// Reads the RGB color at integer pixel `point` (top-left origin). Returns
    /// nil if the point is out of bounds or the image can't be read.
    static func color(at point: CGPoint, in image: CGImage) -> ColorFormatProvider.RGB? {
        let x = Int(point.x)
        let y = Int(point.y)
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * image.width
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        guard let context = CGContext(
            data: &pixels,
            width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        let offset = y * bytesPerRow + x * bytesPerPixel
        return ColorFormatProvider.RGB(
            r: Int(pixels[offset]),
            g: Int(pixels[offset + 1]),
            b: Int(pixels[offset + 2])
        )
    }

    /// Formats a sampled color for display: "#RRGGBB · rgb(r, g, b)".
    static func describe(_ rgb: ColorFormatProvider.RGB) -> String {
        "\(ColorFormatProvider.toHex(rgb)) · rgb(\(rgb.r), \(rgb.g), \(rgb.b))"
    }
}

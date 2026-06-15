import CoreGraphics
import Foundation

enum WatermarkPosition: String, CaseIterable, Identifiable {
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"
    case center = "Center"
    case tiled = "Tiled"

    var id: String { rawValue }
}

/// Pure geometry for placing a watermark within an image. Coordinates use a
/// bottom-left origin (CoreGraphics). Fully unit-testable.
enum WatermarkLayout {
    /// The frame for a single watermark of `markSize` inside `imageSize` at the
    /// given position, inset by `margin`.
    static func frame(
        position: WatermarkPosition,
        imageSize: CGSize,
        markSize: CGSize,
        margin: CGFloat
    ) -> CGRect {
        let maxX = imageSize.width - markSize.width - margin
        let maxY = imageSize.height - markSize.height - margin
        let origin: CGPoint
        switch position {
        case .topLeft: origin = CGPoint(x: margin, y: maxY)
        case .topRight: origin = CGPoint(x: maxX, y: maxY)
        case .bottomLeft: origin = CGPoint(x: margin, y: margin)
        case .bottomRight: origin = CGPoint(x: maxX, y: margin)
        case .center, .tiled:
            origin = CGPoint(x: (imageSize.width - markSize.width) / 2,
                             y: (imageSize.height - markSize.height) / 2)
        }
        return CGRect(origin: origin, size: markSize)
    }

    /// For tiled placement, the origins of each repeated mark across the image.
    static func tileOrigins(imageSize: CGSize, markSize: CGSize, spacing: CGFloat) -> [CGPoint] {
        guard markSize.width > 0, markSize.height > 0 else { return [] }
        let stepX = markSize.width + spacing
        let stepY = markSize.height + spacing
        var origins: [CGPoint] = []
        var y: CGFloat = 0
        while y < imageSize.height {
            var x: CGFloat = 0
            while x < imageSize.width {
                origins.append(CGPoint(x: x, y: y))
                x += stepX
            }
            y += stepY
        }
        return origins
    }
}

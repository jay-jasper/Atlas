import CoreGraphics
import Foundation

/// Computes overlay guide rectangles for common aspect ratios, centered within
/// a container. Pure geometry — fully unit-testable. Used by the recording
/// composition overlay (#45).
enum AspectRatioPreset: String, CaseIterable, Identifiable {
    case vertical9x16 = "9:16"
    case square1x1 = "1:1"
    case portrait4x5 = "4:5"
    case wide16x9 = "16:9"
    case cinema21x9 = "21:9"

    var id: String { rawValue }

    /// width:height ratio as a Double.
    var ratio: Double {
        switch self {
        case .vertical9x16: return 9.0 / 16.0
        case .square1x1: return 1.0
        case .portrait4x5: return 4.0 / 5.0
        case .wide16x9: return 16.0 / 9.0
        case .cinema21x9: return 21.0 / 9.0
        }
    }
}

enum AspectRatioGuide {
    /// Returns the largest rect of the preset's aspect ratio that fits inside
    /// `container`, centered.
    static func fittedRect(preset: AspectRatioPreset, in container: CGSize) -> CGRect {
        guard container.width > 0, container.height > 0 else { return .zero }
        let targetRatio = preset.ratio
        let containerRatio = container.width / container.height

        let size: CGSize
        if containerRatio > targetRatio {
            // Container is wider — height-constrained.
            let height = container.height
            size = CGSize(width: height * targetRatio, height: height)
        } else {
            // Container is taller — width-constrained.
            let width = container.width
            size = CGSize(width: width, height: width / targetRatio)
        }
        let origin = CGPoint(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2
        )
        return CGRect(origin: origin, size: size)
    }
}

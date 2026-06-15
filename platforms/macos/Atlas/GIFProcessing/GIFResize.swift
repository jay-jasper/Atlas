import CoreGraphics
import Foundation

/// Pure resize-dimension math for GIF re-encoding. Fully unit-testable.
enum GIFResize {
    /// Scales `source` by `factor`, rounding to whole pixels (min 1×1).
    static func scaled(_ source: CGSize, by factor: Double) -> CGSize {
        CGSize(
            width: max(1, (source.width * CGFloat(factor)).rounded()),
            height: max(1, (source.height * CGFloat(factor)).rounded())
        )
    }

    /// Fits `source` within `maxDimension` on its longest edge, preserving the
    /// aspect ratio. Never upscales.
    static func fitted(_ source: CGSize, maxDimension: CGFloat) -> CGSize {
        let longest = max(source.width, source.height)
        guard longest > maxDimension, longest > 0 else { return source }
        return scaled(source, by: Double(maxDimension / longest))
    }

    /// Estimated frame delay (seconds) when targeting a frame rate. Clamped to
    /// GIF's 0.02s minimum granularity.
    static func frameDelay(targetFPS: Double) -> Double {
        guard targetFPS > 0 else { return 0.1 }
        return max(0.02, (1.0 / targetFPS * 100).rounded() / 100)
    }
}

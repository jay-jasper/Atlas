import CoreGraphics
import Foundation

/// Pure scroll math for the teleprompter. Fully unit-testable.
enum TeleprompterEngine {
    /// Vertical scroll offset (points) for `elapsed` seconds at `speed`
    /// (points/second), clamped so content never scrolls past its end.
    static func offset(elapsed: TimeInterval, speed: Double, contentHeight: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        let maxOffset = max(0, contentHeight - viewportHeight)
        let raw = CGFloat(elapsed * speed)
        return min(max(0, raw), maxOffset)
    }

    /// Scroll progress in 0...1.
    static func progress(offset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) -> Double {
        let maxOffset = max(0, contentHeight - viewportHeight)
        guard maxOffset > 0 else { return 1 }
        return Double(min(max(0, offset), maxOffset) / maxOffset)
    }

    /// Whether scrolling has reached the end.
    static func isComplete(offset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) -> Bool {
        offset >= max(0, contentHeight - viewportHeight)
    }
}

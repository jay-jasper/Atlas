import Foundation

/// Pure scroll-smoothing math. Accumulates discrete scroll deltas into a target
/// and emits eased per-frame steps toward it. Deterministic & unit-testable.
struct ScrollSmoothingEngine {
    /// 0 = no smoothing (instant), approaching 1 = very smooth/slow.
    var smoothing: Double
    /// Multiplies incoming deltas (acceleration).
    var step: Double

    private(set) var remaining: Double = 0

    init(smoothing: Double = 0.85, step: Double = 1.0) {
        self.smoothing = min(max(smoothing, 0), 0.99)
        self.step = step
    }

    /// Adds an incoming scroll delta to the pending distance.
    mutating func addDelta(_ delta: Double) {
        remaining += delta * step
    }

    /// Returns the amount to scroll this frame, reducing `remaining`.
    /// When the remainder is tiny it flushes fully to avoid lingering drift.
    mutating func nextFrame() -> Double {
        guard remaining != 0 else { return 0 }
        let move = remaining * (1 - smoothing)
        // Flush the tail so motion actually completes.
        if abs(remaining) <= 1 || abs(move) < 0.1 {
            let all = remaining
            remaining = 0
            return all
        }
        remaining -= move
        return move
    }

    var isAnimating: Bool { remaining != 0 }
}

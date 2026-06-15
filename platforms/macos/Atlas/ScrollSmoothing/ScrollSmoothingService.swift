import Foundation

@MainActor
final class ScrollSmoothingService: ObservableObject {
    @Published var smoothing: Double = 0.85 {
        didSet { engine.smoothing = min(max(smoothing, 0), 0.99) }
    }
    @Published var step: Double = 1.2 {
        didSet { engine.step = step }
    }
    @Published var isEnabled = false {
        didSet { isEnabled ? start() : stop() }
    }
    @Published private(set) var statusMessage = ""

    private(set) var engine = ScrollSmoothingEngine()

    /// Feeds an incoming wheel delta and returns the smoothed value to emit this
    /// frame. Exposed for testing the smoothing pipeline without an event tap.
    func process(delta: Double) -> Double {
        engine.addDelta(delta)
        return engine.nextFrame()
    }

    private func start() {
        // A real implementation installs a CGEventTap on scrollWheel events and
        // replaces line-deltas with smoothed pixel-deltas on a display-linked
        // timer. Requires Accessibility permission.
        statusMessage = "Smoothing enabled (per-app rules apply)."
    }

    private func stop() {
        statusMessage = ""
    }
}

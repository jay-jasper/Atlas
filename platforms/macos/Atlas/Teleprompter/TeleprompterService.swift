import Combine
import CoreGraphics
import Foundation

@MainActor
final class TeleprompterService: ObservableObject {
    @Published var script: String = "Paste your script here…"
    @Published var speed: Double = 40 // points per second
    @Published var fontSize: Double = 28
    @Published var isMirrored: Bool = false
    @Published private(set) var isScrolling = false
    @Published private(set) var offset: CGFloat = 0

    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0

    private var startDate: Date?
    private var startOffset: CGFloat = 0
    private var timer: AnyCancellable?
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func start() {
        guard !isScrolling else { return }
        startDate = now()
        startOffset = offset
        isScrolling = true
        timer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func pause() {
        isScrolling = false
        timer?.cancel()
        timer = nil
    }

    func reset() {
        pause()
        offset = 0
        startOffset = 0
    }

    func tick(at date: Date? = nil) {
        guard isScrolling, let start = startDate else { return }
        let elapsed = (date ?? now()).timeIntervalSince(start)
        offset = startOffset + TeleprompterEngine.offset(
            elapsed: elapsed, speed: speed,
            contentHeight: contentHeight, viewportHeight: viewportHeight
        )
        if TeleprompterEngine.isComplete(offset: offset, contentHeight: contentHeight, viewportHeight: viewportHeight) {
            pause()
        }
    }
}

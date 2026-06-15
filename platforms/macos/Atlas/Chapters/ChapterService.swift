import Foundation

@MainActor
final class ChapterService: ObservableObject {
    @Published private(set) var markers: [ChapterMarker] = []
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed = 0

    private var startDate: Date?
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func start() {
        startDate = now()
        isRecording = true
        elapsed = 0
        markers = []
    }

    func stop() {
        isRecording = false
        startDate = nil
    }

    /// Adds a marker at the current elapsed time.
    func mark(title: String, at date: Date? = nil) {
        guard isRecording, let start = startDate else { return }
        let seconds = Int((date ?? now()).timeIntervalSince(start))
        elapsed = seconds
        let name = title.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Chapter \(markers.count + 1)"
            : title
        markers.append(ChapterMarker(seconds: seconds, title: name))
    }

    func remove(id: UUID) {
        markers.removeAll { $0.id == id }
    }

    func tick(at date: Date? = nil) {
        guard isRecording, let start = startDate else { return }
        elapsed = Int((date ?? now()).timeIntervalSince(start))
    }

    func export(as format: ChapterExporter.Format) -> String {
        ChapterExporter.export(markers, as: format)
    }
}

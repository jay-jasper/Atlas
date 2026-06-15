import Foundation

@MainActor
final class TextExpansionService: ObservableObject {
    @Published private(set) var snippets: [TextSnippet] = []
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var isMonitoring: Bool = false

    private let store: TextExpansionStoring
    private let monitor: TextExpansionMonitoring

    init(
        store: TextExpansionStoring = TextExpansionStore(),
        monitor: TextExpansionMonitoring = TextExpansionMonitor()
    ) {
        self.store = store
        self.monitor = monitor
        reload()
        monitor.onResolveExpansion = { [weak self] buffer in
            guard let self else { return nil }
            return TextExpansionEngine.match(buffer: buffer, snippets: self.snippets)
        }
    }

    func reload() {
        snippets = store.snippets()
    }

    func add(trigger: String, expansion: String) {
        do {
            try store.upsert(TextSnippet(trigger: trigger, expansion: expansion))
            statusMessage = ""
            reload()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func delete(id: UUID) {
        try? store.delete(id: id)
        reload()
    }

    func startMonitoring() {
        isMonitoring = monitor.start()
        if !isMonitoring {
            statusMessage = "Accessibility permission required for live expansion."
        }
    }

    func stopMonitoring() {
        monitor.stop()
        isMonitoring = false
    }
}

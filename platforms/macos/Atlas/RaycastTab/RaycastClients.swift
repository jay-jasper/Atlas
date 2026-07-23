import Foundation

/// Rust FFI 薄包装:notes/focus/transfer/AI 指令。存储根 `Application Support/Atlas/`,
/// 与 AIChatBridge 的 `Atlas/ai` 同级(notes/focus 子目录由 Rust 自建)。
enum RaycastStorage {
    static let root: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Atlas", isDirectory: true)

    private static var wired = false

    /// 幂等;首次调用注入 Rust 存储根。
    static func wire() {
        guard !wired else { return }
        wired = true
        notesSetStorageDir(path: root.path)
        focusSetStorageDir(path: root.path)
        // AI 指令库挂在 ai 存储根下;先于 AIChatBridge 初始化时也要可用。
        aiSetStorageDir(path: root.appendingPathComponent("ai", isDirectory: true).path)
    }
}

@MainActor
final class NotesClient: ObservableObject {
    @Published private(set) var notes: [NoteMeta] = []
    @Published var lastError: String?

    init() {
        RaycastStorage.wire()
        refresh()
    }

    func refresh() {
        notes = (try? notesList()) ?? []
    }

    func note(id: String) -> NoteContent? {
        try? notesGet(id: id)
    }

    @discardableResult
    func save(id: String?, title: String, body: String) -> String? {
        do {
            let savedID = try notesSave(id: id, title: title, bodyMd: body)
            refresh()
            return savedID
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func delete(id: String) {
        try? notesDelete(id: id)
        refresh()
    }

    func togglePin(id: String) {
        _ = try? notesTogglePin(id: id)
        refresh()
    }

    func search(_ query: String) -> [NoteMeta] {
        (try? notesSearch(query: query)) ?? []
    }
}

@MainActor
final class FocusClient: ObservableObject {
    @Published private(set) var status: FocusStatus = FocusStatus(phase: .idle, config: nil, remainingSecs: 0)
    @Published private(set) var history: [FocusSessionRecord] = []

    init() {
        RaycastStorage.wire()
        refresh()
    }

    func refresh() {
        status = (try? focusState()) ?? FocusStatus(phase: .idle, config: nil, remainingSecs: 0)
        history = (try? focusHistory()) ?? []
    }

    @discardableResult
    func start(goal: String, minutes: UInt32, blocked: [String], dnd: Bool) -> Bool {
        let config = FocusConfig(
            goal: goal, durationMin: minutes,
            blockedBundleIds: blocked, enableDnd: dnd
        )
        let ok = (try? focusStart(config: config)) != nil
        refresh()
        return ok
    }

    func pause() { _ = try? focusPause(); refresh() }
    func resume() { _ = try? focusResume(); refresh() }
    func stop() { try? focusStop(); refresh() }
}

@MainActor
final class AiCommandsClient: ObservableObject {
    @Published private(set) var commands: [AiCommandEntry] = []
    @Published var lastError: String?

    init() {
        refresh()
    }

    func refresh() {
        commands = (try? aiCommandsList()) ?? []
    }

    func save(_ command: AiCommandEntry) {
        do {
            try aiCommandsSave(command: command)
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func delete(id: String) {
        do {
            try aiCommandsDelete(id: id)
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }
}

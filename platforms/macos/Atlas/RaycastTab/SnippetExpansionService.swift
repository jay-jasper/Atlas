import AppKit
import Carbon.HIToolbox
import Foundation

/// 片段自动展开执行层:EventTapService 订阅者。
/// 命中关键词 → 回删关键词 → 解析 placeholders → 粘贴展开文本 → {cursor} 回移。
@MainActor
final class SnippetExpansionService: ObservableObject {
    static let shared = SnippetExpansionService()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            applyState()
        }
    }

    private static let enabledKey = "snippets.autoexpand.enabled"
    private var engine = SnippetExpansionEngine()
    private let store: SnippetStore
    private var expanding = false

    init(store: SnippetStore = SnippetStore()) {
        self.store = store
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        reloadEntries()
        applyState()
    }

    func reloadEntries() {
        let entries = store.snippets().compactMap { snippet -> SnippetExpansionEngine.Entry? in
            guard let keyword = SnippetKeywordStore.keyword(for: snippet.id), !keyword.isEmpty else {
                return nil
            }
            return SnippetExpansionEngine.Entry(id: snippet.id, keyword: keyword, body: snippet.body)
        }
        engine.updateEntries(entries)
    }

    private func applyState() {
        if isEnabled, EventTapService.shared.isAccessibilityTrusted {
            EventTapService.shared.subscribe(id: "snippet-expansion") { [weak self] event, type in
                self?.handle(event: event, type: type) ?? event
            }
        } else {
            EventTapService.shared.unsubscribe(id: "snippet-expansion")
        }
    }

    private nonisolated func handle(event: CGEvent, type: CGEventType) -> CGEvent? {
        if type == .leftMouseDown {
            Task { @MainActor in self.engineReset() }
            return event
        }
        guard type == .keyDown else { return event }
        // 自己注入的事件不回流。
        guard event.getIntegerValueField(.eventSourceUserData) != Self.injectedMarker else {
            return event
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        var text = keyCharacters(event: event)
        if keyCode == kVK_Delete { text = "\u{8}" }
        guard !text.isEmpty else { return event }
        Task { @MainActor in
            for ch in text {
                if let match = self.engineIngest(ch) {
                    self.expand(match: match)
                    break
                }
            }
        }
        return event
    }

    private func engineIngest(_ ch: Character) -> SnippetExpansionEngine.Match? {
        engine.ingest(ch)
    }

    private func engineReset() {
        engine.reset()
    }

    private nonisolated func keyCharacters(event: CGEvent) -> String {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        return String(utf16CodeUnits: chars, count: length)
    }

    // MARK: - Expansion

    static let injectedMarker: Int64 = 0x41544C53_5345 // 'ATLSSE'

    private func expand(match: SnippetExpansionEngine.Match) {
        guard !expanding else { return }
        expanding = true
        defer { expanding = false }

        // {argument:} 先弹窗收参。
        let prompts = SnippetPlaceholderParser.argumentPrompts(in: match.body)
        var argumentValues: [String] = []
        for prompt in prompts {
            let alert = NSAlert()
            alert.messageText = prompt.isEmpty ? loc("输入参数", "Enter argument") : prompt
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
            alert.accessoryView = field
            alert.addButton(withTitle: loc("确定", "OK"))
            alert.addButton(withTitle: loc("取消", "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            argumentValues.append(field.stringValue)
        }

        let resolved = SnippetPlaceholderParser.resolve(
            match.body,
            context: .live(argumentValues: argumentValues)
        )

        // 回删关键词。
        postKey(keyCode: CGKeyCode(kVK_Delete), count: match.keyword.count)
        // 粘贴展开文本(保存/恢复剪贴板)。
        pasteText(resolved.text)
        // {cursor} 回移。
        if let offset = resolved.cursorOffsetFromEnd, offset > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.postKey(keyCode: CGKeyCode(kVK_LeftArrow), count: offset)
            }
        }
    }

    private func postKey(keyCode: CGKeyCode, count: Int) {
        guard count > 0, let source = CGEventSource(stateID: .combinedSessionState) else { return }
        for _ in 0..<count {
            for down in [true, false] {
                guard let event = CGEvent(
                    keyboardEventSource: source, virtualKey: keyCode, keyDown: down
                ) else { continue }
                event.setIntegerValueField(.eventSourceUserData, value: Self.injectedMarker)
                event.post(tap: .cgSessionEventTap)
            }
        }
    }

    private func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data]? in
            var copies: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { copies[type] = data }
            }
            return copies.isEmpty ? nil : copies
        } ?? []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // ⌘V 注入。
        if let source = CGEventSource(stateID: .combinedSessionState) {
            for down in [true, false] {
                guard let event = CGEvent(
                    keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down
                ) else { continue }
                event.flags = .maskCommand
                event.setIntegerValueField(.eventSourceUserData, value: Self.injectedMarker)
                event.post(tap: .cgSessionEventTap)
            }
        }

        // 稍后恢复剪贴板(粘贴异步完成)。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            pasteboard.clearContents()
            for saved in savedItems {
                let item = NSPasteboardItem()
                for (type, data) in saved {
                    item.setData(data, forType: type)
                }
                pasteboard.writeObjects([item])
            }
        }
    }
}

/// 片段 id → 展开关键词(独立存储,SnippetStore 结构不动)。
enum SnippetKeywordStore {
    private static let key = "snippets.expansion.keywords"

    static func all() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    static func keyword(for id: String) -> String? {
        all()[id]
    }

    static func set(_ keyword: String?, for id: String) {
        var map = all()
        if let keyword, !keyword.isEmpty {
            map[id] = keyword
        } else {
            map.removeValue(forKey: id)
        }
        UserDefaults.standard.set(map, forKey: key)
    }
}

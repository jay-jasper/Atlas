import AppKit
import ApplicationServices
import Foundation

/// AI 指令执行:取选中文本(AX 优先,剪贴板兜底)→ 渲染 prompt →
/// AiOneShotRunner 流式 → 按 output_mode 面板/粘贴/复制。
@MainActor
final class AICommandRunner: ObservableObject {
    static let shared = AICommandRunner()

    @Published var activeCommand: AiCommandEntry?
    @Published private(set) var selectionUsed: String = ""
    let runner = AiOneShotRunner()

    /// 前台选中文本:AX 失败降级剪贴板。
    static func currentSelection() -> String {
        if let axText = axSelectedText(), !axText.isEmpty {
            return axText
        }
        return NSPasteboard.general.string(forType: .string) ?? ""
    }

    private static func axSelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system, kAXFocusedUIElementAttribute as CFString, &focused
        ) == .success, let element = focused else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected
        ) == .success else { return nil }
        return selected as? String
    }

    func run(_ command: AiCommandEntry, selection: String? = nil) {
        let text = selection ?? Self.currentSelection()
        selectionUsed = text
        activeCommand = command
        let prompt = aiCommandsRender(template: command.promptTemplate, selection: text)
        runner.run(prompt: prompt) { [weak self] result in
            self?.deliver(result, mode: command.output)
        }
    }

    private func deliver(_ result: String, mode: AiCommandOutputMode) {
        switch mode {
        case .panel:
            break // 结果留在 runner.output,由面板展示
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result, forType: .string)
        case .paste:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result, forType: .string)
            // ⌘V 注入到前台(需要辅助功能;失败则内容已在剪贴板)。
            if let source = CGEventSource(stateID: .combinedSessionState) {
                for down in [true, false] {
                    let event = CGEvent(
                        keyboardEventSource: source,
                        virtualKey: 9, // kVK_ANSI_V
                        keyDown: down
                    )
                    event?.flags = .maskCommand
                    event?.post(tap: .cgSessionEventTap)
                }
            }
        }
    }
}

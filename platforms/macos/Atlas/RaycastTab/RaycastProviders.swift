import AppKit
import Foundation

/// 笔记:新建 + 最近/搜索(queryDriven)。
final class NotesProvider: CommandProviding {
    private let openTab: () -> Void

    init(openTab: @escaping () -> Void) {
        self.openTab = openTab
    }

    func results(for query: String) -> [PaletteCommand] {
        let isChineseUI = AppLanguage.current == .zh
        let category = isChineseUI ? "笔记" : "Notes"
        var commands: [PaletteCommand] = [
            PaletteCommand(
                id: UUID(),
                title: isChineseUI ? "新建笔记" : "New Note",
                subtitle: isChineseUI ? "在 Raycast tab 打开编辑" : "Opens the Raycast tab editor",
                icon: .sfSymbol("square.and.pencil"),
                keywords: ["note", "笔记", "新建", "biji", "xinjian"],
                action: .execute { [openTab] in
                    _ = try? notesSave(id: nil, title: "新笔记", bodyMd: "")
                    openTab()
                },
                category: category
            ),
        ]
        let q = query.trimmingCharacters(in: .whitespaces)
        let metas = (q.isEmpty ? (try? notesList()) : (try? notesSearch(query: q))) ?? []
        commands += metas.prefix(6).map { meta in
            PaletteCommand(
                id: UUID(),
                title: meta.title.isEmpty ? "(无标题)" : meta.title,
                subtitle: isChineseUI ? "打开笔记" : "Open note",
                icon: .sfSymbol(meta.pinned ? "pin" : "note.text"),
                keywords: ["note", "笔记", meta.title],
                action: .execute { [openTab] in openTab() },
                category: category
            )
        }
        if !q.isEmpty {
            // 只有命中笔记或命令名时才回结果(引擎还会再筛)。
            return commands.filter {
                $0.title.localizedCaseInsensitiveContains(q)
                    || $0.keywords.contains { $0.localizedCaseInsensitiveContains(q) }
            }
        }
        return commands
    }
}

/// 专注:开始(参数=目标)/暂停/结束。
final class FocusCommandsProvider: CommandProviding {
    func results(for query: String) -> [PaletteCommand] {
        let isChineseUI = AppLanguage.current == .zh
        let category = isChineseUI ? "专注" : "Focus"
        let phase = (try? focusState())?.phase ?? .idle

        var commands: [PaletteCommand] = []
        if phase == .idle {
            commands.append(PaletteCommand(
                id: UUID(),
                title: isChineseUI ? "开始专注" : "Start Focus",
                subtitle: isChineseUI ? "25 分钟(在 Raycast tab 可配)" : "25 min (configure in Raycast tab)",
                icon: .sfSymbol("timer"),
                keywords: ["focus", "专注", "番茄", "zhuanzhu", "pomodoro"],
                action: .execute {
                    Task { @MainActor in
                        let blocked = UserDefaults.standard.stringArray(forKey: "focus.blocked") ?? []
                        FocusService.shared.start(goal: "专注", minutes: 25, blocked: blocked, dnd: false)
                    }
                },
                category: category
            ))
        } else {
            commands.append(PaletteCommand(
                id: UUID(),
                title: isChineseUI ? "结束专注" : "End Focus",
                subtitle: nil,
                icon: .sfSymbol("stop.circle"),
                keywords: ["focus", "专注", "结束", "stop"],
                action: .execute {
                    Task { @MainActor in FocusService.shared.stop() }
                },
                category: category
            ))
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return commands }
        return commands.filter { cmd in
            cmd.title.localizedCaseInsensitiveContains(q)
                || cmd.keywords.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }
}

/// 翻译:`tr 文本` 即时行(queryDriven)。
final class TranslateProvider: CommandProviding {
    func results(for query: String) -> [PaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let isChineseUI = AppLanguage.current == .zh
        let category = isChineseUI ? "翻译" : "Translate"

        guard trimmed.lowercased().hasPrefix("tr "), trimmed.count > 3 else {
            // 裸 `tr`/`翻译` 给入口提示行。
            if ["tr", "翻译", "fanyi"].contains(trimmed.lowercased()) {
                return [PaletteCommand(
                    id: UUID(),
                    title: isChineseUI ? "翻译:tr <文本>" : "Translate: tr <text>",
                    subtitle: isChineseUI ? "回车打开翻译面板" : "Enter opens the translate pane",
                    icon: .sfSymbol("character.bubble"),
                    keywords: ["translate", "翻译", "fanyi", "tr"],
                    action: .execute {
                        Task { @MainActor in AtlasServices.shared.openMainWindow?() }
                    },
                    category: category
                )]
            }
            return []
        }
        let text = String(trimmed.dropFirst(3))
        return [PaletteCommand(
            id: UUID(),
            title: (isChineseUI ? "翻译:" : "Translate: ") + text,
            subtitle: isChineseUI ? "AI 引擎 · 结果复制到剪贴板" : "AI engine · result copied",
            icon: .sfSymbol("character.bubble"),
            keywords: ["translate", "翻译", "tr", text],
            action: .execute {
                Task { @MainActor in
                    TranslateService.shared.translate(text) { result in
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result, forType: .string)
                    }
                }
            },
            category: category
        )]
    }
}

/// AI 指令:每条一行,执行=当前选中文本。
final class AICommandsProvider: CommandProviding {
    func results(for query: String) -> [PaletteCommand] {
        let isChineseUI = AppLanguage.current == .zh
        let category = isChineseUI ? "AI 指令" : "AI Commands"
        let commands = ((try? aiCommandsList()) ?? []).map { command in
            PaletteCommand(
                id: UUID(),
                title: command.name,
                subtitle: isChineseUI ? "对选中文本执行" : "Runs on selected text",
                icon: .sfSymbol(command.icon),
                keywords: ["ai", "指令", command.name, "zhiling"],
                action: .execute {
                    Task { @MainActor in AICommandRunner.shared.run(command) }
                },
                category: category
            )
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return commands }
        return commands.filter { cmd in
            cmd.title.localizedCaseInsensitiveContains(q)
                || cmd.keywords.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }
}

/// 听写:开始/停止粘贴。
final class DictationProvider: CommandProviding {
    func results(for query: String) -> [PaletteCommand] {
        let isChineseUI = AppLanguage.current == .zh
        let category = isChineseUI ? "听写" : "Dictation"
        let isRecording = MainActor.assumeIsolated { DictationService.shared.isRecording }
        let command: PaletteCommand
        if isRecording {
            command = PaletteCommand(
                id: UUID(),
                title: isChineseUI ? "停止听写并粘贴" : "Stop Dictation & Paste",
                subtitle: nil,
                icon: .sfSymbol("mic.slash"),
                keywords: ["dictation", "听写", "语音", "tingxie"],
                action: .execute {
                    Task { @MainActor in DictationService.shared.pasteTranscript() }
                },
                category: category
            )
        } else {
            command = PaletteCommand(
                id: UUID(),
                title: isChineseUI ? "开始听写" : "Start Dictation",
                subtitle: isChineseUI ? "本地语音识别,停止后粘贴到前台" : "On-device speech; pastes on stop",
                icon: .sfSymbol("mic"),
                keywords: ["dictation", "听写", "语音输入", "tingxie", "yuyin"],
                action: .execute {
                    Task { @MainActor in
                        DictationService.shared.requestPermissions { granted in
                            if granted { DictationService.shared.start() }
                        }
                    }
                },
                category: category
            )
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [command] }
        return [command].filter { cmd in
            cmd.title.localizedCaseInsensitiveContains(q)
                || cmd.keywords.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }
}

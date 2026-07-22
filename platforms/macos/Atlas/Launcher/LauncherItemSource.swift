import AppKit
import Foundation

// MARK: - Source protocol

protocol LauncherItemSource {
    var sourceID: String { get }
    func items(for query: String) -> [LauncherItem]
}

/// Providers may adopt this to contribute extra ⌘K actions per command.
protocol LauncherActionEnriching {
    func extraActions(for command: PaletteCommand) -> [LauncherAction]
}

// MARK: - Adapter over legacy CommandProviding

struct CommandProviderAdapter: LauncherItemSource {
    let sourceID: String
    private let provider: CommandProviding
    private let onLegacyPush: (PaletteDestination) -> LauncherPage

    init(
        provider: CommandProviding,
        sourceID: String,
        onLegacyPush: @escaping (PaletteDestination) -> LauncherPage = { .legacy($0) }
    ) {
        self.provider = provider
        self.sourceID = sourceID
        self.onLegacyPush = onLegacyPush
    }

    func items(for query: String) -> [LauncherItem] {
        provider.results(for: query).map { makeItem(from: $0) }
    }

    private func makeItem(from command: PaletteCommand) -> LauncherItem {
        let isAnswer = command.category == "Calculator" || command.category == "Conversion"
        var actions = [primaryAction(for: command)]

        if isAnswer {
            let answer = command.subtitle ?? command.title
            actions.append(copyAction(id: "copy-answer", title: "Copy Answer", text: answer))
        }

        var detail: LauncherDetail?
        if command.category == "Files" {
            let path = command.subtitle ?? ""
            detail = LauncherDetail.forFile(path: path)
            actions.append(
                LauncherAction(
                    id: "reveal",
                    title: "Reveal in Finder",
                    systemImage: "folder",
                    shortcutHint: "⌘F"
                ) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    return .dismiss
                }
            )
            actions.append(copyAction(id: "copy-path", title: "Copy Path", text: path, hint: "⌘P"))
        } else if command.category == "Clipboard" {
            detail = LauncherDetail(previewText: command.title)
        }

        if !isAnswer {
            actions.append(copyAction(id: "copy-title", title: "Copy Title", text: command.title, hint: "⌘C"))
        }

        if let enriching = provider as? LauncherActionEnriching {
            actions.append(contentsOf: enriching.extraActions(for: command))
        }

        return LauncherItem(
            id: CommandUsageStore.commandKey(for: command),
            title: command.title,
            subtitle: command.subtitle,
            icon: command.icon,
            keywords: command.keywords,
            category: command.category,
            actions: actions,
            detail: detail,
            isAnswer: isAnswer
        )
    }

    private func primaryAction(for command: PaletteCommand) -> LauncherAction {
        switch command.action {
        case .execute(let fn):
            return LauncherAction(id: "run", title: "Run", systemImage: "return", shortcutHint: "↵") {
                fn()
                return .dismiss
            }
        case .push(let destination):
            let page = onLegacyPush(destination)
            return LauncherAction(id: "open", title: "Open", systemImage: "arrow.right", shortcutHint: "↵") {
                .push(page)
            }
        }
    }

    private func copyAction(id: String, title: String, text: String, hint: String? = nil) -> LauncherAction {
        LauncherAction(id: id, title: title, systemImage: "doc.on.doc", shortcutHint: hint) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .dismiss
        }
    }
}

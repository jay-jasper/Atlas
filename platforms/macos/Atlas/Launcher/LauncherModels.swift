import AppKit
import Foundation

// MARK: - Actions

struct LauncherAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let shortcutHint: String?
    let perform: () -> LauncherActionOutcome

    init(
        id: String,
        title: String,
        systemImage: String,
        shortcutHint: String? = nil,
        perform: @escaping () -> LauncherActionOutcome
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.shortcutHint = shortcutHint
        self.perform = perform
    }
}

enum LauncherActionOutcome {
    case dismiss
    case stay
    case push(LauncherPage)
}

// MARK: - Sections

enum LauncherSection: Hashable {
    case answer
    case favorites
    case recents
    case results(String)
    case fallback
}

// MARK: - Detail

struct LauncherDetail {
    struct Row: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }

    let rows: [Row]
    let previewText: String?
    let previewImagePath: String?

    init(rows: [Row] = [], previewText: String? = nil, previewImagePath: String? = nil) {
        self.rows = rows
        self.previewText = previewText
        self.previewImagePath = previewImagePath
    }

    static func forFile(path: String) -> LauncherDetail? {
        let manager = FileManager.default
        guard !path.isEmpty, manager.fileExists(atPath: path) else { return nil }
        let attributes = (try? manager.attributesOfItem(atPath: path)) ?? [:]

        var rows: [Row] = [
            Row(label: "Name", value: (path as NSString).lastPathComponent),
            Row(label: "Path", value: path),
        ]
        if let size = attributes[.size] as? Int64 {
            rows.append(Row(label: "Size", value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))
        }
        if let modified = attributes[.modificationDate] as? Date {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            rows.append(Row(label: "Modified", value: formatter.string(from: modified)))
        }

        let ext = (path as NSString).pathExtension.lowercased()
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "tiff", "webp", "bmp"]
        return LauncherDetail(
            rows: rows,
            previewText: nil,
            previewImagePath: imageExtensions.contains(ext) ? path : nil
        )
    }
}

// MARK: - Pages

enum LauncherPage {
    case list(title: String, items: () -> [LauncherItem])
    case grid(title: String, columns: Int, items: () -> [LauncherItem])
    case detail(title: String, detail: LauncherDetail)
    case legacy(PaletteDestination)
}

// MARK: - Item

struct LauncherItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: PaletteIcon
    let keywords: [String]
    let category: String
    var actions: [LauncherAction]
    var detail: LauncherDetail?
    var isAnswer: Bool
    var acceptsArgument: Bool

    // MARK: 搜索标注(引擎填充,瞬态)
    /// 综合得分(匹配 + frecency),仅在一次搜索管线内有效。
    var searchScore: Double = 0
    /// 标题高亮:命中字符的 Character 序号(nil = 无高亮)。
    var titleHighlightOffsets: [Int]?
    /// 该命令的 alias(有则行尾显示胶囊)。
    var aliasBadge: String?

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        icon: PaletteIcon,
        keywords: [String] = [],
        category: String,
        actions: [LauncherAction],
        detail: LauncherDetail? = nil,
        isAnswer: Bool = false,
        acceptsArgument: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.keywords = keywords
        self.category = category
        self.actions = actions
        self.detail = detail
        self.isAnswer = isAnswer
        self.acceptsArgument = acceptsArgument
    }

    var primaryAction: LauncherAction? { actions.first }
}

// MARK: - Query parsing

enum LauncherQueryParser {
    /// "gh swift charts" → (head: "gh", remainder: "swift charts")
    static func split(_ query: String) -> (head: String, remainder: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let spaceIndex = trimmed.firstIndex(where: { $0 == " " }) else {
            return (trimmed, "")
        }
        let head = String(trimmed[..<spaceIndex])
        let remainder = String(trimmed[trimmed.index(after: spaceIndex)...])
            .trimmingCharacters(in: .whitespaces)
        return (head, remainder)
    }
}

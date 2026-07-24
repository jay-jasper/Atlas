import AppKit
import SwiftUI

struct LauncherSectionHeader: View {
    let title: String
    let fontSize: Double

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: max(fontSize - 4, 10), weight: .semibold))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

struct LauncherResultRow: View {
    let item: LauncherItem
    let isSelected: Bool
    let style: LauncherStyle
    let accent: Color
    var indexBadge: Int?

    /// 命中字符加粗 + 强调色。
    private var highlightedTitle: Text {
        guard let offsets = item.titleHighlightOffsets, !offsets.isEmpty else {
            return Text(item.title)
        }
        let hits = Set(offsets)
        var attributed = AttributedString()
        for (index, character) in item.title.enumerated() {
            var piece = AttributedString(String(character))
            if hits.contains(index) {
                piece.foregroundColor = accent
                piece.font = .system(size: style.fontSize, weight: .bold)
            }
            attributed += piece
        }
        return Text(attributed)
    }

    var body: some View {
        HStack(spacing: 10) {
            LauncherIconView(icon: item.icon, size: style.iconSize, accent: accent)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                highlightedTitle
                    .font(.system(size: style.fontSize))
                    .lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: max(style.fontSize - 3, 10)))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let alias = item.aliasBadge {
                Text(alias)
                    .font(.system(size: max(style.fontSize - 5, 9), design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(accent.opacity(0.15), in: Capsule())
            }

            if let indexBadge {
                Text("⌘\(indexBadge)")
                    .font(.system(size: max(style.fontSize - 5, 9), weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }

            if item.category != "Files" {
                Text(item.category == "App" ? "Application" : item.category)
                    .font(.system(size: max(style.fontSize - 3, 10)))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: style.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? accent.opacity(0.18) : Color.clear)
                .padding(.horizontal, 6)
        )
        .contentShape(Rectangle())
        .focusable(false)
    }
}

struct LauncherAnswerCard: View {
    let item: LauncherItem
    let isSelected: Bool
    let style: LauncherStyle
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.system(size: style.fontSize + 1))
                .foregroundColor(.secondary)
            Text(item.subtitle ?? item.title)
                .font(.system(size: style.fontSize + 14, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(accent.opacity(isSelected ? 0.22 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accent.opacity(isSelected ? 0.8 : 0.25), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .focusable(false)
    }
}

struct LauncherIconView: View {
    let icon: PaletteIcon
    let size: Double
    let accent: Color

    @State private var appImage: NSImage?

    var body: some View {
        Group {
            switch icon {
            case .sfSymbol(let name):
                Image(systemName: name)
                    .font(.system(size: size / 2))
                    .frame(width: size, height: size)
                    .background(accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: size / 4.5))
            case .appIcon(let url):
                Group {
                    if let appImage {
                        Image(nsImage: appImage)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "app")
                            .font(.system(size: size / 2))
                    }
                }
                .frame(width: size, height: size)
                .task(id: url) {
                    let image = NSWorkspace.shared.icon(forFile: url.path)
                    image.size = CGSize(width: size, height: size)
                    appImage = image
                }
            }
        }
    }
}

struct LauncherDetailPane: View {
    let detail: LauncherDetail
    let style: LauncherStyle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let imagePath = detail.previewImagePath,
                   let image = NSImage(contentsOfFile: imagePath) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if let text = detail.previewText {
                    Text(text)
                        .font(.system(size: style.fontSize - 1))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(detail.rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label)
                            .font(.system(size: max(style.fontSize - 4, 9), weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(row.value)
                            .font(.system(size: style.fontSize - 2))
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.primary.opacity(0.04))
    }
}

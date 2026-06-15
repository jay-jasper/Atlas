import SwiftUI

/// Faithful SwiftUI recreation of the design prototype's command palette
/// (`Atlas Palette.dc.html`): 640-wide frosted panel, mono query input, grouped
/// results with category badges, an emoji row, and the keyboard-hint footer.
struct AtlasPaletteScreen: View {
    @Environment(\.colorScheme) private var scheme
    var onClose: () -> Void = {}

    var body: some View {
        let theme = AtlasTheme.resolve(for: scheme)
        AtlasPopupChrome {
            VStack(spacing: 0) {
                queryBar(theme)
                ScrollView {
                    VStack(spacing: 0) {
                        groupLabel(theme, "计算")
                        calculatorResult(theme)
                        groupLabel(theme, "建议")
                        result(theme, icon: "xcode", iconStyle: .gradient([Color(hex: "147efb"), Color(hex: "0a4ea8")]),
                               title: "Launch Xcode", subtitle: "/Applications/Xcode.app · 上次使用 9 分钟前",
                               badge: "App", badgeTint: theme.text2, badgeBg: theme.input, trailing: .enter)
                        result(theme, icon: "rectangle.righthalf.inset.filled", iconStyle: .plain,
                               title: "Move to right half", subtitle: "Window Manager · 当前窗口 → 右半屏",
                               badge: "Window", badgeTint: theme.text2, badgeBg: theme.input, trailing: .shortcut("⌃⌥→"))
                        snippetResult(theme)
                        emojiResult(theme)
                        result(theme, icon: "doc.text", iconStyle: .tint(theme.red),
                               title: "atlas-spec.pdf", subtitle: "~/Documents/atlas/atlas-spec.pdf · 2.4 MB · 昨天 18:32",
                               badge: "Files", badgeTint: theme.red, badgeBg: theme.redSoft, trailing: .enter)
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 460)
                footer(theme)
            }
        }
        .frame(width: 640)
        .environment(\.atlasTheme, theme)
    }

    // MARK: - Pieces

    private func queryBar(_ theme: AtlasTheme) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 17)).foregroundStyle(theme.text2)
            Text("= 413 * 3 + 18")
                .font(.system(size: 17, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.text1)
            Spacer(minLength: 0)
            kbd(theme, "⌘K")
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.text3).frame(width: 22, height: 22)
                    .background(theme.input, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .overlay(Rectangle().fill(theme.divider).frame(height: 1), alignment: .bottom)
    }

    private func groupLabel(_ theme: AtlasTheme, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1)
                .foregroundStyle(theme.text3)
            Rectangle().fill(theme.divider).frame(height: 1)
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
    }

    private func calculatorResult(_ theme: AtlasTheme) -> some View {
        HStack(spacing: 12) {
            resultIcon(theme, system: "equal.square", style: .accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("= 1257").font(.system(size: 16, weight: .semibold, design: .monospaced)).foregroundStyle(theme.text1)
                Text("413 × 3 + 18 · 整数").font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.text3)
            }
            Spacer(minLength: 0)
            badgeView(theme, "Calculator", tint: theme.accentText, bg: theme.accentSoft)
            kbd(theme, "⏎")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(theme.accentSoft)
        .overlay(Rectangle().fill(theme.accent).frame(width: 2.5).padding(.vertical, 6), alignment: .leading)
    }

    private func snippetResult(_ theme: AtlasTheme) -> some View {
        HStack(spacing: 12) {
            resultIcon(theme, system: "chevron.left.forwardslash.chevron.right", style: .tint(theme.orange))
            VStack(alignment: .leading, spacing: 2) {
                (Text(":gitlog ").foregroundColor(theme.orange) + Text("→ ").foregroundColor(theme.text3)
                    + Text("git log --oneline -n 20 --graph").foregroundColor(theme.text1))
                    .font(.system(size: 13, design: .monospaced))
                Text("Snippet · 自动粘贴到当前 App").font(.system(size: 11)).foregroundStyle(theme.text3)
            }
            Spacer(minLength: 0)
            badgeView(theme, "Snippet", tint: theme.orange, bg: theme.orangeSoft)
            kbd(theme, "⏎")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func emojiResult(_ theme: AtlasTheme) -> some View {
        HStack(alignment: .top, spacing: 12) {
            resultIcon(theme, system: "face.smiling", style: .plain)
            VStack(alignment: .leading, spacing: 6) {
                Text("smile").font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text1)
                HStack(spacing: 6) {
                    ForEach(Array(["😊", "😄", "😀", "🙂", "😺", "☺️", "🥲", "😌"].enumerated()), id: \.offset) { idx, e in
                        Text(e).font(.system(size: 18)).padding(4)
                            .background(idx == 0 ? theme.accentSoft : theme.section, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(idx == 0 ? theme.accentStrong : theme.divider, lineWidth: 1))
                    }
                }
            }
            Spacer(minLength: 0)
            badgeView(theme, "Emoji", tint: theme.text2, bg: theme.input)
            kbd(theme, "⏎")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private enum IconStyle { case plain, accent, tint(Color), gradient([Color]) }
    private enum Trailing { case enter, shortcut(String) }

    private func result(_ theme: AtlasTheme, icon: String, iconStyle: IconStyle, title: String,
                        subtitle: String, badge: String, badgeTint: Color, badgeBg: Color, trailing: Trailing) -> some View {
        HStack(spacing: 12) {
            resultIcon(theme, system: icon, style: iconStyle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text1)
                Text(subtitle).font(.system(size: 11, design: subtitle.contains("/") ? .monospaced : .default)).foregroundStyle(theme.text3).lineLimit(1)
            }
            Spacer(minLength: 0)
            switch trailing {
            case .enter:
                badgeView(theme, badge, tint: badgeTint, bg: badgeBg); kbd(theme, "⏎")
            case .shortcut(let s):
                kbd(theme, s); badgeView(theme, badge, tint: badgeTint, bg: badgeBg)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func resultIcon(_ theme: AtlasTheme, system: String, style: IconStyle) -> some View {
        let fg: Color
        let bg: AnyShapeStyle
        var border = theme.divider
        switch style {
        case .plain: fg = theme.text2; bg = AnyShapeStyle(theme.section)
        case .accent: fg = theme.accentText; bg = AnyShapeStyle(theme.accentSoft); border = theme.accentStrong
        case .tint(let c): fg = c; bg = AnyShapeStyle(theme.section)
        case .gradient(let colors): fg = .white; bg = AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)); border = .clear
        }
        return Image(systemName: system).font(.system(size: 14)).foregroundStyle(fg)
            .frame(width: 28, height: 28)
            .background(bg, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(border, lineWidth: 1))
    }

    private func badgeView(_ theme: AtlasTheme, _ text: String, tint: Color, bg: Color) -> some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.3)
            .foregroundStyle(tint).padding(.horizontal, 7).padding(.vertical, 2)
            .background(bg, in: Capsule())
    }

    private func kbd(_ theme: AtlasTheme, _ text: String) -> some View {
        Text(text).font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.text2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(theme.input, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.border, lineWidth: 1))
    }

    private func footer(_ theme: AtlasTheme) -> some View {
        HStack(spacing: 14) {
            ForEach([("↑↓", "导航"), ("⏎", "执行"), ("⌘⏎", "复制"), ("⇥", "切换分类")], id: \.0) { key, label in
                HStack(spacing: 5) { kbd(theme, key); Text(label) }
            }
            Spacer(minLength: 0)
            Button("回到 Atlas", action: onClose).buttonStyle(.plain).foregroundStyle(theme.text3)
        }
        .font(.system(size: 11)).foregroundStyle(theme.text3)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(theme.section)
        .overlay(Rectangle().fill(theme.divider).frame(height: 1), alignment: .top)
    }
}

import SwiftUI

/// Faithful recreation of the prototype's edition / licensing screen
/// (`Atlas Edition.dc.html`): header with current-tier pill, a three-column
/// Free / Pro / Community comparison (Pro highlighted with an accent gradient and
/// CURRENT badge), an "已解锁" capability list, a "需权限" grant list, and the
/// SHA-256-verified license footer.
struct AtlasEditionScreen: View {
    @Environment(\.colorScheme) private var scheme
    var onBack: () -> Void = {}

    private struct Tier: Identifiable {
        let id = UUID()
        let name: String
        let price: String
        let blurb: String
        let features: [(String, Bool)]
        let current: Bool
    }

    private let tiers: [Tier] = [
        Tier(name: "Free", price: "¥0", blurb: "核心工具 · 永久免费", features: [
            ("系统监控 · 端口管理", true),
            ("截图 · 区域 / 窗口", true),
            ("命令面板 · 计算 / 启动", true),
            ("Scene 自动化", false),
            ("本地转录 · AI Skills", false),
            ("插件运行时", false),
        ], current: false),
        Tier(name: "Pro", price: "¥188/年", blurb: "全部模块 · 优先更新", features: [
            ("Free 全部能力", true),
            ("Scene 自动化 · 无限场景", true),
            ("本地转录 · 实时字幕", true),
            ("AI Skills · TokenBar", true),
            ("插件运行时 · MCP Hub", true),
            ("优先技术支持", true),
        ], current: true),
        Tier(name: "Community", price: "自托管", blurb: "开源 · 自行编译", features: [
            ("全部源码能力", true),
            ("自行编译签名", true),
            ("社区插件仓库", true),
            ("官方云同步", false),
            ("捆绑授权许可", false),
            ("官方技术支持", false),
        ], current: false),
    ]

    private struct Unlocked: Identifiable { let id = UUID(); let name: String; let on: Bool }
    private let unlocked: [Unlocked] = [
        Unlocked(name: "AI Skills", on: true),
        Unlocked(name: "TokenBar", on: true),
        Unlocked(name: "本地转录", on: false),
        Unlocked(name: "插件运行时", on: true),
        Unlocked(name: "代理切换", on: true),
    ]

    private struct Grant: Identifiable { let id = UUID(); let name: String; let detail: String }
    private let grants: [Grant] = [
        Grant(name: "实时字幕", detail: "需语音识别授权"),
        Grant(name: "文本扩展", detail: "需辅助功能授权"),
    ]

    var body: some View {
        let theme = AtlasTheme.resolve(for: scheme)
        AtlasPopupChrome {
            VStack(spacing: 0) {
                header(theme)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        tierColumns(theme)
                        unlockedSection(theme)
                        grantSection(theme)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                }
                footer(theme)
            }
        }
        .frame(width: 460, height: 720)
        .environment(\.atlasTheme, theme)
    }

    private func header(_ theme: AtlasTheme) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.text2).frame(width: 24, height: 24)
                        .background(theme.section, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Text("版本").font(.system(size: 15, weight: .semibold))
                Text("Edition").font(.system(size: 11)).foregroundStyle(theme.text3)
                Spacer(minLength: 0)
                AtlasPill(text: "当前 Pro · bundled", tint: theme.accentText, background: theme.accentSoft)
            }
            HStack(spacing: 0) {
                Text("授权来自 ")
                Text("app-bundle").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(theme.text2)
                Text(" · 41 解锁 · 8 可解锁")
            }
            .font(.system(size: 11)).foregroundStyle(theme.text3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .overlay(Rectangle().fill(theme.divider).frame(height: 1), alignment: .bottom)
    }

    private func tierColumns(_ theme: AtlasTheme) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(tiers) { tierColumn(theme, $0) }
        }
    }

    private func tierColumn(_ theme: AtlasTheme, _ tier: Tier) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text(tier.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.text1)
                Spacer(minLength: 0)
                if tier.current {
                    Text("CURRENT").font(.system(size: 8, weight: .bold)).tracking(0.5)
                        .foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(theme.accent, in: Capsule())
                }
            }
            Text(tier.price).font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(tier.current ? theme.accentText : theme.text1)
            Text(tier.blurb).font(.system(size: 9.5)).foregroundStyle(theme.text3).lineLimit(1)
            Rectangle().fill(theme.divider).frame(height: 1).padding(.vertical, 1)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(tier.features.enumerated()), id: \.offset) { _, feat in
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: feat.1 ? "checkmark" : "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(feat.1 ? theme.green : theme.text3)
                            .frame(width: 10)
                        Text(feat.0).font(.system(size: 10))
                            .foregroundStyle(feat.1 ? theme.text2 : theme.text3)
                            .strikethrough(!feat.1, color: theme.text3)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            tier.current
                ? AnyShapeStyle(LinearGradient(colors: [theme.accentSoft, theme.section],
                                               startPoint: .top, endPoint: .bottom))
                : AnyShapeStyle(theme.section),
            in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay(RoundedRectangle(cornerRadius: 9)
            .stroke(tier.current ? theme.accentStrong : theme.divider, lineWidth: tier.current ? 1.5 : 1))
    }

    private func unlockedSection(_ theme: AtlasTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(theme, "已解锁")
            FlowChips(items: unlocked.map(\.id)) { id in
                let item = unlocked.first { $0.id == id }!
                HStack(spacing: 4) {
                    Text(item.name).font(.system(size: 11, weight: .medium)).foregroundStyle(theme.text1)
                    if item.on {
                        Text("✓ ON").font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.green)
                    } else {
                        Text("未开启").font(.system(size: 9)).foregroundStyle(theme.text3)
                    }
                }
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(item.on ? theme.greenSoft : theme.section, in: Capsule())
                .overlay(Capsule().stroke(item.on ? .clear : theme.divider, lineWidth: 1))
            }
        }
    }

    private func grantSection(_ theme: AtlasTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(theme, "需权限")
            VStack(spacing: 7) {
                ForEach(grants) { grant in
                    HStack(spacing: 9) {
                        Image(systemName: "lock.shield").font(.system(size: 13)).foregroundStyle(theme.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(grant.name).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.text1)
                            Text(grant.detail).font(.system(size: 10.5)).foregroundStyle(theme.text3)
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 3) {
                            Text("授权"); Image(systemName: "arrow.right").font(.system(size: 8, weight: .bold))
                        }
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(theme.accentText)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(theme.accentSoft, in: Capsule())
                    }
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .background(theme.section, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.divider, lineWidth: 1))
                }
            }
        }
    }

    private func sectionTitle(_ theme: AtlasTheme, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(theme.text2)
            Rectangle().fill(theme.divider).frame(height: 1)
        }
    }

    private func footer(_ theme: AtlasTheme) -> some View {
        HStack(spacing: 8) {
            Text("app-bundle").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(theme.text3)
            Text("· SHA-256 ·").foregroundStyle(theme.text3)
            HStack(spacing: 3) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 10)).foregroundStyle(theme.green)
                Text("已验证").foregroundStyle(theme.green)
            }
            Spacer(minLength: 0)
            Button {} label: {
                HStack(spacing: 3) { Text("Manage License"); Image(systemName: "arrow.right").font(.system(size: 8, weight: .bold)) }
                    .foregroundStyle(theme.accentText).fontWeight(.medium)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(theme.section)
        .overlay(Rectangle().fill(theme.divider).frame(height: 1), alignment: .top)
    }
}

/// A minimal wrapping chip row used by the Edition screen's "已解锁" list.
private struct FlowChips<ID: Hashable, Chip: View>: View {
    let items: [ID]
    @ViewBuilder let chip: (ID) -> Chip

    var body: some View {
        // A simple two-column-friendly wrap: SwiftUI lacks a native flow layout on
        // the macOS 13 target, so we lay chips left-to-right and wrap manually.
        WrapHStack(items: items, spacing: 6, chip: chip)
    }
}

/// Greedy line-wrapping horizontal stack (macOS 13-compatible).
private struct WrapHStack<ID: Hashable, Chip: View>: View {
    let items: [ID]
    let spacing: CGFloat
    @ViewBuilder let chip: (ID) -> Chip

    @State private var rows: [[ID]] = []

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(chunked().enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.self) { chip($0) }
                }
            }
        }
    }

    /// Fixed-size greedy chunking (3 chips per row) — deterministic and
    /// layout-engine-free, matching the prototype's compact pill grid.
    private func chunked() -> [[ID]] {
        stride(from: 0, to: items.count, by: 3).map {
            Array(items[$0 ..< min($0 + 3, items.count)])
        }
    }
}

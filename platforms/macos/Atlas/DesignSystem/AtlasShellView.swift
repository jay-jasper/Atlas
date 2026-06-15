import SwiftUI

/// A faithful SwiftUI implementation of the approved design prototype's main
/// Shell popup (`Atlas Shell.dc.html`): brand header, Scene Center card, the
/// live monitoring section, and footer — built on AtlasTheme + components.
/// Parameterized so real services can drive it; defaults mirror the mockup.
struct AtlasShellView: View {
    @Environment(\.colorScheme) private var scheme

    // Hooks (no-ops by default; wire to real navigation/services when adopted).
    var onOpenPalette: () -> Void = {}
    var onOpenPreferences: () -> Void = {}
    var onOpenScene: () -> Void = {}
    var onOpenToggles: () -> Void = {}

    var body: some View {
        let theme = AtlasTheme.resolve(for: scheme)
        AtlasPopupChrome {
            VStack(spacing: 0) {
                header(theme)
                AtlasSceneCenterCard(
                    sceneName: "Focus",
                    reason: reasonText(theme),
                    activatedAgo: "激活 23 分钟前",
                    modules: ["监控", "Pomodoro", "剪贴板", "TOTP"],
                    extraModuleCount: 2,
                    onEdit: onOpenScene
                )
                .padding(.horizontal, 10)
                .padding(.top, 10)

                ScrollView {
                    VStack(spacing: 0) {
                        monitoringSection(theme)
                        divider(theme)
                        nowPlayingHeader(theme)
                    }
                }
                footer(theme)
            }
        }
        .frame(width: 460, height: 720)
        .atlasTheme(scheme)
        .environment(\.atlasTheme, theme)
    }

    // MARK: - Header

    private func header(_ theme: AtlasTheme) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                AtlasLogoNode(size: 26)
                Text("Atlas").font(.system(size: 14.5, weight: .semibold))
                Button(action: onOpenScene) {
                    HStack(spacing: 5) {
                        Circle().fill(theme.accent).frame(width: 5, height: 5)
                        Text("Focus").font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(theme.text1)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(theme.section, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    iconButton("magnifyingglass", theme, action: onOpenPalette)
                    iconButton("shield.lefthalf.filled", theme) {}
                    iconButton("gearshape", theme, action: onOpenPreferences)
                    iconButton("ellipsis", theme) {}
                }
            }
            HStack(spacing: 8) {
                Circle().fill(theme.green).frame(width: 6, height: 6)
                    .overlay(Circle().stroke(theme.greenSoft, lineWidth: 3))
                (Text("Local").foregroundColor(theme.text1).fontWeight(.medium)
                    + Text(" · 6 modules active · 14 后台服务在线").foregroundColor(theme.text2))
                    .font(.system(size: 11.5))
                Spacer(minLength: 0)
                Text("⌘K").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(theme.text3)
            }
            .padding(.leading, 36)
        }
        .padding(.horizontal, 12)
        .padding(.top, 13)
        .padding(.bottom, 11)
        .background(LinearGradient(colors: [theme.section, .clear], startPoint: .top, endPoint: .bottom))
        .overlay(Rectangle().fill(theme.divider).frame(height: 1), alignment: .bottom)
    }

    private func iconButton(_ symbol: String, _ theme: AtlasTheme, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(theme.text2)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Monitoring

    private func monitoringSection(_ theme: AtlasTheme) -> some View {
        VStack(spacing: 0) {
            AtlasSectionHeader(systemImage: "chart.line.uptrend.xyaxis", title: "系统监控") {
                AtlasPill(text: "LIVE", tint: theme.green, background: theme.greenSoft)
            }
            VStack(spacing: 9) {
                HStack(spacing: 8) {
                    AtlasMetricTile(value: "37", unit: "% CPU", fraction: 0.37, barColor: theme.accent)
                    AtlasMetricTile(value: "12.4", unit: "/ 16 GB", fraction: 0.775, barColor: theme.blue)
                    netTile(theme)
                }
                coresBar(theme)
                processRows(theme)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    private func netTile(_ theme: AtlasTheme) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("↓2.1").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(theme.green)
                Text("↑180K").font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.text2)
            }
            Text("MB/s · KB/s").font(.system(size: 10)).foregroundStyle(theme.text3)
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.section, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.divider, lineWidth: 1))
    }

    private func coresBar(_ theme: AtlasTheme) -> some View {
        let cores: [(Double, Color)] = [
            (0.62, theme.accent), (0.28, theme.accent), (0.81, theme.orange), (0.44, theme.accent),
            (0.22, theme.accent), (0.92, theme.red), (0.36, theme.accent), (0.18, theme.accent),
            (0.51, theme.accent), (0.33, theme.accent),
        ]
        return HStack(spacing: 6) {
            Text("Cores").font(.system(size: 10, weight: .medium)).foregroundStyle(theme.text3)
            HStack(spacing: 3) {
                ForEach(Array(cores.enumerated()), id: \.offset) { _, core in
                    GeometryReader { geo in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2).fill(theme.input)
                            RoundedRectangle(cornerRadius: 2).fill(core.1.opacity(0.85))
                                .frame(height: geo.size.height * core.0)
                        }
                    }
                    .frame(height: 18)
                }
            }
        }
    }

    private func processRows(_ theme: AtlasTheme) -> some View {
        VStack(spacing: 4) {
            processRow(theme, badge: "Xc", badgeColor: theme.red, badgeBg: theme.redSoft,
                       name: "Xcode", detail: "build · 8123", cpu: "82%", cpuColor: theme.red, mem: "3.4 GB")
            processRow(theme, badge: "Ar", badgeColor: theme.blue, badgeBg: theme.blueSoft,
                       name: "Arc", detail: "helper · 412", cpu: "21%", cpuColor: theme.orange, mem: "1.8 GB")
            processRow(theme, badge: "ol", badgeColor: theme.text2, badgeBg: theme.input,
                       name: "ollama-serve", detail: "9213", cpu: "14%", cpuColor: theme.text2, mem: "2.1 GB")
        }
    }

    private func processRow(_ theme: AtlasTheme, badge: String, badgeColor: Color, badgeBg: Color,
                            name: String, detail: String, cpu: String, cpuColor: Color, mem: String) -> some View {
        HStack(spacing: 6) {
            Text(badge)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(badgeColor)
                .frame(width: 14, height: 14)
                .background(badgeBg, in: RoundedRectangle(cornerRadius: 3))
            Text(name).foregroundStyle(theme.text1)
            Text(detail).font(.system(size: 10.5)).foregroundStyle(theme.text3)
            Spacer(minLength: 0)
            Text(cpu).font(.system(size: 11.5, weight: .medium, design: .monospaced)).foregroundStyle(cpuColor)
            Text(mem).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(theme.text3).frame(width: 48, alignment: .trailing)
        }
        .font(.system(size: 11.5))
    }

    private func nowPlayingHeader(_ theme: AtlasTheme) -> some View {
        AtlasSectionHeader(systemImage: "music.note", title: "Now Playing") {
            Text("Apple Music").font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.text3)
        }
    }

    private func divider(_ theme: AtlasTheme) -> some View {
        Rectangle().fill(theme.divider).frame(height: 1).padding(.horizontal, 14).padding(.vertical, 4)
    }

    // MARK: - Footer

    private func footer(_ theme: AtlasTheme) -> some View {
        HStack(spacing: 10) {
            (Text("Atlas ") + Text("0.8.2-beta").font(.system(size: 11, design: .monospaced)))
                .foregroundStyle(theme.text3)
            Text("·").foregroundStyle(theme.borderStrong)
            (Text("已启用 ") + Text("23").foregroundColor(theme.text1).fontWeight(.medium) + Text(" / 64 模块"))
                .foregroundStyle(theme.text3)
            Spacer(minLength: 0)
            Text("Pro").foregroundStyle(theme.text3)
            Text("·").foregroundStyle(theme.borderStrong)
            Button(action: onOpenToggles) {
                HStack(spacing: 3) { Text("模块选配"); Image(systemName: "arrow.right").font(.system(size: 8, weight: .bold)) }
                    .foregroundStyle(theme.accentText).fontWeight(.medium)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(theme.section)
        .overlay(Rectangle().fill(theme.divider).frame(height: 1), alignment: .top)
    }

    private func reasonText(_ theme: AtlasTheme) -> AttributedString {
        var s = AttributedString("由 Xcode 前台 + Pomodoro 自动激活")
        if let range = s.range(of: "Xcode") {
            s[range].foregroundColor = theme.text1
            s[range].font = .system(size: 11.5, weight: .medium)
        }
        return s
    }
}

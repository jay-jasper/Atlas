import SwiftUI

/// Live data the Shell renders when wired to real services. Any field left at its
/// default keeps the prototype's mock value, so the view degrades gracefully.
struct AtlasShellLiveData: Equatable {
    struct Process: Equatable {
        var badge: String
        var name: String
        var detail: String
        var cpu: String
    }
    var cpuPercent: Int
    var memUsedGB: Double
    var memTotalGB: Double
    var netDownText: String
    var netDownUnit: String
    var netUpText: String
    var cores: [Double]
    var processes: [Process]
    var sceneName: String?
    var enabledCount: Int
    var totalCount: Int
    var activeModuleCount: Int
    var nowPlayingSource: String?
}

/// A faithful SwiftUI implementation of the approved design prototype's main
/// Shell popup (`Atlas Shell.dc.html`): brand header, Scene Center card, the
/// live monitoring section, and footer — built on AtlasTheme + components.
/// Parameterized so real services can drive it; defaults mirror the mockup.
struct AtlasShellView: View {
    @Environment(\.colorScheme) private var scheme

    // Real data (nil → prototype mock values).
    var live: AtlasShellLiveData? = nil

    // Hooks (no-ops by default; wire to real navigation/services when adopted).
    var onOpenPalette: () -> Void = {}
    var onOpenPreferences: () -> Void = {}
    var onOpenScene: () -> Void = {}
    var onOpenToggles: () -> Void = {}
    var onOpenMore: () -> Void = {}

    var body: some View {
        let theme = AtlasTheme.resolve(for: scheme)
        AtlasPopupChrome {
            VStack(spacing: 0) {
                header(theme)
                AtlasSceneCenterCard(
                    sceneName: live?.sceneName ?? "Focus",
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
                    iconButton("ellipsis", theme, action: onOpenMore)
                }
            }
            HStack(spacing: 8) {
                Circle().fill(theme.green).frame(width: 6, height: 6)
                    .overlay(Circle().stroke(theme.greenSoft, lineWidth: 3))
                (Text("Local").foregroundColor(theme.text1).fontWeight(.medium)
                    + Text(" · \(live?.activeModuleCount ?? 6) modules active · 14 后台服务在线").foregroundColor(theme.text2))
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
                    cpuTile(theme)
                    memTile(theme)
                    netTile(theme)
                }
                coresBar(theme)
                processRows(theme)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    private func cpuTile(_ theme: AtlasTheme) -> some View {
        let pct = live?.cpuPercent ?? 37
        return AtlasMetricTile(value: "\(pct)", unit: "% CPU", fraction: Double(pct) / 100, barColor: theme.accent)
    }

    private func memTile(_ theme: AtlasTheme) -> some View {
        let used = live?.memUsedGB ?? 12.4
        let total = live?.memTotalGB ?? 16
        let value = String(format: used >= 10 ? "%.1f" : "%.2f", used)
        return AtlasMetricTile(value: value, unit: "/ \(Int(total.rounded())) GB",
                               fraction: total > 0 ? used / total : 0, barColor: theme.blue)
    }

    private func netTile(_ theme: AtlasTheme) -> some View {
        let down = live.map { "↓\($0.netDownText)" } ?? "↓2.1"
        let up = live.map { "↑\($0.netUpText)" } ?? "↑180K"
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(down).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(theme.green)
                Text(up).font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.text2)
            }
            Text(live?.netDownUnit ?? "MB/s · KB/s").font(.system(size: 10)).foregroundStyle(theme.text3)
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.section, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.divider, lineWidth: 1))
    }

    private func coresBar(_ theme: AtlasTheme) -> some View {
        let mockUsages: [Double] = [0.62, 0.28, 0.81, 0.44, 0.22, 0.92, 0.36, 0.18, 0.51, 0.33]
        let usages = (live?.cores).flatMap { $0.isEmpty ? nil : $0 } ?? mockUsages
        let cores: [(Double, Color)] = usages.map { u in
            let color: Color = u >= 0.9 ? theme.red : (u >= 0.75 ? theme.orange : theme.accent)
            return (min(max(u, 0), 1), color)
        }
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

    @ViewBuilder
    private func processRows(_ theme: AtlasTheme) -> some View {
        if let procs = live?.processes, !procs.isEmpty {
            let palette: [(Color, Color)] = [(theme.red, theme.redSoft), (theme.blue, theme.blueSoft), (theme.text2, theme.input)]
            VStack(spacing: 4) {
                ForEach(Array(procs.prefix(3).enumerated()), id: \.offset) { idx, p in
                    let pair = palette[idx % palette.count]
                    let pctValue = Int(p.cpu.filter { $0.isNumber }) ?? 0
                    let cpuColor: Color = pctValue >= 80 ? theme.red : (pctValue >= 30 ? theme.orange : theme.text2)
                    processRow(theme, badge: p.badge, badgeColor: pair.0, badgeBg: pair.1,
                               name: p.name, detail: p.detail, cpu: p.cpu, cpuColor: cpuColor, mem: "")
                }
            }
        } else {
            VStack(spacing: 4) {
                processRow(theme, badge: "Xc", badgeColor: theme.red, badgeBg: theme.redSoft,
                           name: "Xcode", detail: "build · 8123", cpu: "82%", cpuColor: theme.red, mem: "3.4 GB")
                processRow(theme, badge: "Ar", badgeColor: theme.blue, badgeBg: theme.blueSoft,
                           name: "Arc", detail: "helper · 412", cpu: "21%", cpuColor: theme.orange, mem: "1.8 GB")
                processRow(theme, badge: "ol", badgeColor: theme.text2, badgeBg: theme.input,
                           name: "ollama-serve", detail: "9213", cpu: "14%", cpuColor: theme.text2, mem: "2.1 GB")
            }
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
            Text(live?.nowPlayingSource ?? "Apple Music").font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.text3)
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
            (Text("已启用 ") + Text("\(live?.enabledCount ?? 23)").foregroundColor(theme.text1).fontWeight(.medium) + Text(" / \(live?.totalCount ?? 64) 模块"))
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

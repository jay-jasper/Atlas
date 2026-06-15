import SwiftUI

/// Faithful recreation of the prototype's Scene editor (`Atlas Scene.dc.html`):
/// a 720×560 window with a scene list sidebar and a detail pane showing the
/// active scene's triggers, module visibility/order table, behavior rules, and a
/// recent-activations diagnostics timeline.
struct AtlasSceneScreen: View {
    @Environment(\.colorScheme) private var scheme
    var onClose: () -> Void = {}

    private struct Scene: Identifiable {
        let id = UUID(); let icon: String; let name: String; let sub: String
        var active: Bool = false; var isNew: Bool = false
    }
    private let scenes: [Scene] = [
        Scene(icon: "scope", name: "Focus", sub: "3 triggers · 7 modules", active: true),
        Scene(icon: "menubar.rectangle", name: "Meeting", sub: "2 triggers · 9 modules"),
        Scene(icon: "chevron.left.forwardslash.chevron.right", name: "Coding", sub: "2 triggers · 11 modules"),
        Scene(icon: "globe", name: "Travel", sub: "1 trigger · 5 modules"),
        Scene(icon: "moon.fill", name: "Off-hours", sub: "1 trigger · 3 modules"),
    ]

    private struct Trigger: Identifiable {
        let id = UUID(); let icon: String; let kind: String
        let status: TriggerStatus; var disabled: Bool = false
    }
    private enum TriggerStatus { case hit, idle, off }

    private struct ModuleRow: Identifiable {
        let id = UUID(); let name: String; let key: String?
        let order: String; let override: OverrideKind; let visible: Bool
    }
    private enum OverrideKind { case promoted, defaultOrder, hidden }

    private let modules: [ModuleRow] = [
        ModuleRow(name: "系统监控", key: "monitoring", order: "↑ 1", override: .promoted, visible: true),
        ModuleRow(name: "Pomodoro", key: nil, order: "↑ 2", override: .promoted, visible: true),
        ModuleRow(name: "剪贴板", key: nil, order: "3", override: .defaultOrder, visible: true),
        ModuleRow(name: "TOTP", key: nil, order: "4", override: .defaultOrder, visible: true),
        ModuleRow(name: "Now Playing", key: nil, order: "5", override: .defaultOrder, visible: true),
        ModuleRow(name: "分应用音量", key: nil, order: "—", override: .hidden, visible: false),
        ModuleRow(name: "RSS", key: nil, order: "—", override: .hidden, visible: false),
    ]

    private struct Rule: Identifiable { let id = UUID(); let icon: String; let name: String; let on: Bool }
    private let rules: [Rule] = [
        Rule(icon: "moon.circle", name: "勿扰模式 自动开启", on: true),
        Rule(icon: "capsule", name: "刘海岛 紧凑模式", on: true),
        Rule(icon: "speaker.slash", name: "声音反馈 静音", on: true),
        Rule(icon: "questionmark.circle", name: "键盘音效 关", on: false),
    ]

    private struct LogEntry: Identifiable {
        let id = UUID(); let time: String; let dot: LogDot; let text: String
        let tag: String; let tagKind: LogDot
    }
    private enum LogDot { case green, gray, orange }

    var body: some View {
        let theme = AtlasTheme.resolve(for: scheme)
        AtlasPopupChrome {
            VStack(spacing: 0) {
                titleBar(theme)
                HStack(spacing: 0) {
                    sidebar(theme)
                    Rectangle().fill(theme.divider).frame(width: 1)
                    detailPane(theme)
                }
            }
        }
        .frame(width: 720, height: 560)
        .environment(\.atlasTheme, theme)
    }

    // MARK: - Title bar

    private func titleBar(_ theme: AtlasTheme) -> some View {
        HStack {
            HStack(spacing: 7) {
                Circle().fill(theme.red).frame(width: 12, height: 12)
                Circle().fill(theme.orange).frame(width: 12, height: 12)
                Circle().fill(theme.green).frame(width: 12, height: 12)
            }
            Spacer(minLength: 0)
            (Text("Scenes ").fontWeight(.semibold).foregroundColor(theme.text1)
                + Text("— Atlas").foregroundColor(theme.text3))
                .font(.system(size: 12.5))
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                pillButton(theme, icon: "plus.forwardslash.minus", "Safe Mode")
                Button("关闭", action: onClose).buttonStyle(.plain)
                    .font(.system(size: 10.5)).foregroundStyle(theme.text2)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(theme.input, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.borderInput, lineWidth: 1))
            }
        }
        .padding(.horizontal, 14).frame(height: 38)
        .background(theme.section)
        .overlay(Rectangle().fill(theme.divider).frame(height: 1), alignment: .bottom)
    }

    private func pillButton(_ theme: AtlasTheme, icon: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 9))
            Text(label).font(.system(size: 10.5))
        }
        .foregroundStyle(theme.text2)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(theme.input, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.borderInput, lineWidth: 1))
    }

    // MARK: - Sidebar

    private func sidebar(_ theme: AtlasTheme) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("场景").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(theme.text3)
                    Spacer(minLength: 0)
                    Image(systemName: "plus").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.text2)
                        .frame(width: 18, height: 18)
                        .background(theme.input, in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.border, lineWidth: 1))
                }
                .padding(.horizontal, 10).padding(.bottom, 10)
                ForEach(scenes) { sceneItem(theme, $0) }
                Rectangle().fill(theme.divider).frame(height: 1).padding(.horizontal, 6).padding(.vertical, 10)
                newSceneItem(theme)
            }
            .padding(.horizontal, 10).padding(.vertical, 14)
        }
        .frame(width: 220)
        .background(theme.section)
    }

    private func sceneItem(_ theme: AtlasTheme, _ scene: Scene) -> some View {
        HStack(spacing: 9) {
            Image(systemName: scene.icon).font(.system(size: 11))
                .foregroundStyle(scene.active ? .white : theme.text2)
                .frame(width: 22, height: 22)
                .background(scene.active ? theme.accent : theme.section, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(scene.active ? theme.accent : theme.divider, lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(scene.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(theme.text1)
                Text(scene.sub).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(theme.text3)
            }
            Spacer(minLength: 0)
            if scene.active {
                Circle().fill(theme.accent).frame(width: 6, height: 6)
                    .overlay(Circle().stroke(theme.accentSoft, lineWidth: 3))
            }
        }
        .padding(.horizontal, scene.active ? 9 : 10).padding(.vertical, scene.active ? 8 : 9)
        .background(scene.active ? theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(scene.active ? theme.accentStrong : .clear, lineWidth: 1))
    }

    private func newSceneItem(_ theme: AtlasTheme) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "plus").font(.system(size: 11, weight: .medium)).foregroundStyle(theme.text2)
                .frame(width: 22, height: 22)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(style: StrokeStyle(lineWidth: 1, dash: [3])).foregroundStyle(theme.divider))
            VStack(alignment: .leading, spacing: 1) {
                Text("新建场景").font(.system(size: 12.5)).foregroundStyle(theme.text1)
                Text("从模板或当前状态").font(.system(size: 10.5)).foregroundStyle(theme.text3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .opacity(0.65)
    }

    // MARK: - Detail pane

    private func detailPane(_ theme: AtlasTheme) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                detailHeader(theme)
                triggersSection(theme)
                modulesSection(theme)
                rulesSection(theme)
                diagnosticsSection(theme)
            }
            .padding(.horizontal, 22).padding(.vertical, 18)
        }
        .frame(maxWidth: .infinity)
    }

    private func detailHeader(_ theme: AtlasTheme) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [theme.accent, theme.accentText], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: "scope").font(.system(size: 16)).foregroundStyle(.white))
                    .shadow(color: theme.accentSoft, radius: 5, y: 4)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Focus").font(.system(size: 17, weight: .semibold))
                        Text("激活中").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.green).padding(.horizontal, 7).padding(.vertical, 1)
                            .background(theme.greenSoft, in: Capsule())
                    }
                    (Text("由 ").foregroundColor(theme.text2)
                        + Text("Xcode").foregroundColor(theme.text1).fontWeight(.medium)
                        + Text(" 前台 + Pomodoro 自动激活 · 已运行 23 分钟").foregroundColor(theme.text2))
                        .font(.system(size: 11.5))
                }
                Spacer(minLength: 0)
                smallButton(theme, "复制"); smallButton(theme, "导出")
            }
            .padding(.bottom, 14)
            Rectangle().fill(theme.divider).frame(height: 1)
        }
    }

    private func smallButton(_ theme: AtlasTheme, _ label: String) -> some View {
        Button(label) {}.buttonStyle(.plain)
            .font(.system(size: 11.5)).foregroundStyle(theme.text1)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(theme.input, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.borderInput, lineWidth: 1))
    }

    private func sectionTitle(_ theme: AtlasTheme, _ text: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(theme.accent).frame(width: 3, height: 11)
            Text(text.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(theme.text2)
        }
    }

    private func triggersSection(_ theme: AtlasTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(theme, "触发器")
            VStack(spacing: 7) {
                triggerRow(theme, icon: "square.grid.2x2", label: "前台 App", status: .hit) {
                    HStack(spacing: 5) {
                        appChip(theme, "Xcode", theme.blue)
                        appChip(theme, "Linear", theme.accent)
                        appChip(theme, "Notion", theme.text3)
                        addChip(theme)
                    }
                }
                triggerRow(theme, icon: "keyboard", label: "快捷键", status: .idle) {
                    Text("⌘ ⌥ F").font(.system(size: 12, design: .monospaced)).foregroundStyle(theme.text1)
                }
                triggerRow(theme, icon: "clock", label: "日程", status: .hit) {
                    (Text("Mon–Fri ").foregroundColor(theme.text1)
                        + Text("09:00 – 17:00").font(.system(size: 11.5, design: .monospaced)).foregroundColor(theme.text1))
                        .font(.system(size: 11.5))
                }
                triggerRow(theme, icon: "powerplug", label: "电源", status: .off, disabled: true) {
                    Text("仅 AC 电源 · 已禁用").font(.system(size: 11.5)).foregroundStyle(theme.text2)
                }
            }
        }
    }

    private func triggerRow<Content: View>(_ theme: AtlasTheme, icon: String, label: String,
                                           status: TriggerStatus, disabled: Bool = false,
                                           @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(theme.text2)
                Text(label).font(.system(size: 11.5)).foregroundStyle(theme.text2)
            }
            .frame(width: 110, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
            triggerStatusPill(theme, status)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(theme.section, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.divider, lineWidth: 1))
        .opacity(disabled ? 0.65 : 1)
    }

    @ViewBuilder
    private func triggerStatusPill(_ theme: AtlasTheme, _ status: TriggerStatus) -> some View {
        switch status {
        case .hit:
            Text("✓ 命中").font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.green)
                .padding(.horizontal, 6).padding(.vertical, 2).background(theme.greenSoft, in: Capsule())
        case .idle:
            Text("未触发").font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.text3)
                .padding(.horizontal, 6).padding(.vertical, 2).background(theme.input, in: Capsule())
        case .off:
            Text("关").font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.text3)
                .padding(.horizontal, 6).padding(.vertical, 2).background(theme.input, in: Capsule())
        }
    }

    private func appChip(_ theme: AtlasTheme, _ name: String, _ dot: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(dot).frame(width: 4, height: 4)
            Text(name).font(.system(size: 11)).foregroundStyle(theme.text1)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(theme.input, in: Capsule())
        .overlay(Capsule().stroke(theme.borderInput, lineWidth: 1))
    }

    private func addChip(_ theme: AtlasTheme) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "plus").font(.system(size: 7, weight: .bold))
            Text("添加").font(.system(size: 11))
        }
        .foregroundStyle(theme.text3)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .overlay(Capsule().stroke(style: StrokeStyle(lineWidth: 1, dash: [3])).foregroundStyle(theme.borderInput))
    }

    private func modulesSection(_ theme: AtlasTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(theme, "模块可见度与顺序")
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("").frame(width: 18)
                    Text("模块").frame(maxWidth: .infinity, alignment: .leading)
                    Text("顺序").frame(width: 60, alignment: .leading)
                    Text("状态覆盖").frame(width: 90, alignment: .leading)
                    Text("显示").frame(width: 50)
                }
                .font(.system(size: 10, weight: .semibold)).tracking(0.4).foregroundStyle(theme.text3)
                .padding(.vertical, 6)
                .overlay(Rectangle().fill(theme.divider).frame(height: 1), alignment: .bottom)
                ForEach(Array(modules.enumerated()), id: \.element.id) { idx, m in
                    moduleRow(theme, m, last: idx == modules.count - 1)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(theme.section, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.divider, lineWidth: 1))
        }
    }

    private func moduleRow(_ theme: AtlasTheme, _ m: ModuleRow, last: Bool) -> some View {
        HStack(spacing: 0) {
            Text("⋮⋮").font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.text3).frame(width: 18, alignment: .leading)
            HStack(spacing: 5) {
                Text(m.name).font(.system(size: 11.5, weight: .medium)).foregroundStyle(theme.text1)
                if let key = m.key {
                    Text(key).font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.text3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(m.order).font(.system(size: 11, design: .monospaced))
                .foregroundStyle(m.order == "—" ? theme.text3 : theme.text2).frame(width: 60, alignment: .leading)
            overridePill(theme, m.override).frame(width: 90, alignment: .leading)
            HStack { Spacer(minLength: 0); visSwitch(theme, m.visible); Spacer(minLength: 0) }.frame(width: 50)
        }
        .padding(.vertical, 6)
        .overlay(last ? nil : Rectangle().fill(theme.divider).frame(height: 1), alignment: .bottom)
    }

    @ViewBuilder
    private func overridePill(_ theme: AtlasTheme, _ kind: OverrideKind) -> some View {
        switch kind {
        case .promoted:
            Text("promoted").font(.system(size: 10)).foregroundStyle(theme.accentText)
                .padding(.horizontal, 6).padding(.vertical, 1).background(theme.accentSoft, in: Capsule())
        case .defaultOrder:
            Text("默认").font(.system(size: 10.5)).foregroundStyle(theme.text3)
        case .hidden:
            Text("隐藏").font(.system(size: 10)).foregroundStyle(theme.text3)
                .padding(.horizontal, 6).padding(.vertical, 1).background(theme.input, in: Capsule())
        }
    }

    private func visSwitch(_ theme: AtlasTheme, _ on: Bool) -> some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule().fill(on ? theme.accent : theme.borderStrong).frame(width: 26, height: 15)
            Circle().fill(.white).frame(width: 13, height: 13).padding(1)
                .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
        }
        .frame(width: 26, height: 15)
    }

    private func rulesSection(_ theme: AtlasTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(theme, "行为规则")
            let columns = [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)]
            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(rules) { rule in
                    HStack(spacing: 9) {
                        Image(systemName: rule.icon).font(.system(size: 13)).foregroundStyle(theme.text2)
                        Text(rule.name).font(.system(size: 11.5)).foregroundStyle(theme.text1)
                        Spacer(minLength: 0)
                        visSwitch(theme, rule.on)
                    }
                    .padding(.horizontal, 11).padding(.vertical, 9)
                    .background(theme.section, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.divider, lineWidth: 1))
                    .opacity(rule.on ? 1 : 0.7)
                }
            }
        }
    }

    private func diagnosticsSection(_ theme: AtlasTheme) -> some View {
        let entries: [LogEntry] = [
            LogEntry(time: "2:14 PM", dot: .green, text: "Focus 激活 · 触发: 前台 App = Xcode", tag: "activate", tagKind: .green),
            LogEntry(time: "1:48 PM", dot: .gray, text: "Coding 退出 · 5 秒空闲", tag: "deactivate", tagKind: .gray),
            LogEntry(time: "1:42 PM", dot: .orange, text: "Travel ↔ Focus 冲突 · panelOrder 重叠 · 取 Focus", tag: "resolved", tagKind: .orange),
            LogEntry(time: "11:30 AM", dot: .green, text: "Focus 激活 · 日程 = Mon 09–17", tag: "activate", tagKind: .green),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle(theme, "诊断 · 最近 5 次触发")
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { idx, e in
                    logRow(theme, e, last: idx == entries.count - 1)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(theme.section, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.divider, lineWidth: 1))
        }
    }

    private func logRow(_ theme: AtlasTheme, _ e: LogEntry, last: Bool) -> some View {
        let dotColor: Color = e.dot == .green ? theme.green : (e.dot == .orange ? theme.orange : theme.text3)
        let dotSoft: Color = e.dot == .green ? theme.greenSoft : (e.dot == .orange ? theme.orangeSoft : theme.input)
        return HStack(spacing: 9) {
            Text(e.time).font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.text3).frame(width: 64, alignment: .leading)
            Circle().fill(dotColor).frame(width: 8, height: 8).overlay(Circle().stroke(dotSoft, lineWidth: 3)).frame(width: 14)
            Text(e.text).font(.system(size: 11.5)).foregroundStyle(theme.text1).frame(maxWidth: .infinity, alignment: .leading)
            Text(e.tag).font(.system(size: 10, design: .monospaced)).foregroundStyle(dotColor)
                .padding(.horizontal, 6).padding(.vertical, 1).background(dotSoft, in: Capsule())
        }
        .padding(.vertical, 4)
        .overlay(last ? nil : Rectangle().fill(theme.divider).frame(height: 1), alignment: .bottom)
    }
}

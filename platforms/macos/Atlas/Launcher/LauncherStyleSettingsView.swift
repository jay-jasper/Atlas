import SwiftUI

/// Settings panel for the launcher: appearance customization with live preview,
/// quicklinks, fallback commands, and per-command alias/hotkey assignment.
struct LauncherSettingsPanel: View {
    @ObservedObject var styleStore: LauncherStyleStore
    @ObservedObject var quicklinks: QuicklinkStore
    @ObservedObject var fallbacks: FallbackStore
    @ObservedObject var aliases: AliasStore
    @ObservedObject var hotkeys: CommandHotkeyStore
    let hotkeyConflicts: [String: String]
    let rootItems: () -> [LauncherItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc("启动台外观", "Launcher Appearance"))
                .font(.subheadline)
                .foregroundColor(.secondary)

            LauncherStylePreview(style: styleStore.style.sanitized())

            LauncherStyleControls(styleStore: styleStore)
        }
    }
}

// MARK: - Live preview

struct LauncherStylePreview: View {
    let style: LauncherStyle

    private var accent: Color { style.accent?.color ?? Color.accentColor }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text("Search Atlas…")
                    .font(.system(size: style.fontSize * 0.8))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 26)

            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(accent.opacity(0.25))
                        .frame(width: style.iconSize * 0.4, height: style.iconSize * 0.4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.25))
                        .frame(width: 60 + CGFloat(index) * 18, height: 5)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(height: style.rowHeight * 0.55)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(index == 0 ? accent.opacity(0.18) : Color.clear)
                        .padding(.horizontal, 3)
                )
            }
        }
        .frame(width: max(240, style.panelWidth * 0.58))
        .background(previewBackground)
        .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius * 0.5))
        .overlay(
            RoundedRectangle(cornerRadius: style.cornerRadius * 0.5)
                .stroke(style.borderColor.color, lineWidth: min(style.borderWidth, 2))
        )
        .shadow(radius: 4, y: 2)
        .overlay(alignment: .topTrailing) {
            Text(loc("预览", "Preview"))
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(6)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var previewBackground: some View {
        switch style.background {
        case .theme:
            let theme = ShellThemeKind(
                rawValue: UserDefaults.standard.string(forKey: "atlas.shell.theme") ?? ""
            ) ?? .plain
            theme.spec.makeBackground()
        case .material(let opacity):
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color(nsColor: .windowBackgroundColor).opacity(1 - opacity)
            }
        case .solid(let color):
            color.color
        case .gradient(let from, let to, let angleDegrees):
            LinearGradient(
                colors: [from.color, to.color],
                startPoint: angleDegrees < 90 ? .leading : .top,
                endPoint: angleDegrees < 90 ? .trailing : .bottom
            )
        }
    }
}

// MARK: - Style controls

struct LauncherStyleControls: View {
    @ObservedObject var styleStore: LauncherStyleStore

    private enum BackgroundKind: String, CaseIterable, Identifiable {
        case theme = "主题"
        case material = "毛玻璃"
        case solid = "纯色"
        case gradient = "渐变"
        var id: String { rawValue }
    }

    /// 成套预设:一键套用 背景+边框+圆角,其余项(尺寸/字体)不动。
    struct StylePreset: Identifiable {
        let id: String
        let name: String
        let apply: (inout LauncherStyle) -> Void
    }

    static let presets: [StylePreset] = [
        StylePreset(id: "theme", name: "跟随主题") { style in
            style.background = .theme
            style.borderColor = .clear
            style.borderWidth = 0
            style.cornerRadius = 16
        },
        StylePreset(id: "glass", name: "玻璃") { style in
            style.background = .material(opacity: 0.8)
            style.borderColor = RGBAColor(r: 1, g: 1, b: 1, a: 0.35)
            style.borderWidth = 1
            style.cornerRadius = 18
        },
        StylePreset(id: "night", name: "暗夜") { style in
            style.background = .solid(RGBAColor(r: 0.10, g: 0.10, b: 0.12, a: 1))
            style.borderColor = RGBAColor(r: 1, g: 1, b: 1, a: 0.15)
            style.borderWidth = 1
            style.cornerRadius = 14
        },
        StylePreset(id: "aurora", name: "极光渐变") { style in
            style.background = .gradient(
                RGBAColor(r: 0.30, g: 0.20, b: 0.60, a: 1),
                RGBAColor(r: 0.10, g: 0.35, b: 0.60, a: 1),
                angleDegrees: 135
            )
            style.borderColor = RGBAColor(r: 1, g: 1, b: 1, a: 0.25)
            style.borderWidth = 1
            style.cornerRadius = 20
        },
        StylePreset(id: "minimal", name: "极简白") { style in
            style.background = .solid(RGBAColor(r: 0.98, g: 0.98, b: 0.98, a: 1))
            style.borderColor = RGBAColor(r: 0, g: 0, b: 0, a: 0.12)
            style.borderWidth = 1
            style.cornerRadius = 10
        },
    ]

    private var backgroundKind: BackgroundKind {
        switch styleStore.style.background {
        case .theme: return .theme
        case .material: return .material
        case .solid: return .solid
        case .gradient: return .gradient
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(loc("预设", "Presets"))
                    .font(.caption)
                    .frame(width: 96, alignment: .leading)
                ForEach(Self.presets) { preset in
                    Button(preset.name) {
                        preset.apply(&styleStore.style)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .focusable(false)
                }
                Spacer()
            }

            Picker(loc("背景", "Background"), selection: Binding(
                get: { backgroundKind },
                set: { kind in
                    switch kind {
                    case .theme:
                        styleStore.style.background = .theme
                    case .material:
                        styleStore.style.background = .material(opacity: 0.85)
                    case .solid:
                        styleStore.style.background = .solid(RGBAColor(r: 0.12, g: 0.12, b: 0.14, a: 1))
                    case .gradient:
                        styleStore.style.background = .gradient(
                            RGBAColor(r: 0.16, g: 0.10, b: 0.28, a: 1),
                            RGBAColor(r: 0.05, g: 0.12, b: 0.25, a: 1),
                            angleDegrees: 135
                        )
                    }
                }
            )) {
                ForEach(BackgroundKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            backgroundEditors

            colorRow(loc("边框颜色", "Border"), color: Binding(
                get: { styleStore.style.borderColor },
                set: { styleStore.style.borderColor = $0 }
            ))
            slider(loc("边框宽度", "Border Width"), value: $styleStore.style.borderWidth, in: 0...4, step: 0.5)
            slider(loc("圆角", "Corner Radius"), value: $styleStore.style.cornerRadius, in: 0...28, step: 1)
            slider(loc("面板宽度", "Panel Width"), value: $styleStore.style.panelWidth, in: 480...960, step: 20)
            Stepper(
                loc("可见行数:\(styleStore.style.maxVisibleRows)", "Visible Rows: \(styleStore.style.maxVisibleRows)"),
                value: $styleStore.style.maxVisibleRows,
                in: 4...12
            )
            .font(.caption)
            slider(loc("屏幕位置", "Screen Position"), value: $styleStore.style.topOffsetRatio, in: 0...0.5, step: 0.05)
            Picker(loc("行密度", "Row Density"), selection: $styleStore.style.rowDensity) {
                Text(loc("常规", "Regular")).tag(LauncherStyle.RowDensity.regular)
                Text(loc("紧凑", "Compact")).tag(LauncherStyle.RowDensity.compact)
            }
            .pickerStyle(.segmented)
            slider(loc("字体大小", "Font Size"), value: $styleStore.style.fontSize, in: 13...20, step: 1)
            slider(loc("图标大小", "Icon Size"), value: $styleStore.style.iconSize, in: 24...40, step: 2)

            Toggle(loc("自定义强调色", "Custom Accent"), isOn: Binding(
                get: { styleStore.style.accent != nil },
                set: { on in
                    styleStore.style.accent = on ? RGBAColor(r: 0.35, g: 0.45, b: 1, a: 1) : nil
                }
            ))
            .font(.caption)
            if styleStore.style.accent != nil {
                colorRow(loc("强调色", "Accent"), color: Binding(
                    get: { styleStore.style.accent ?? .white },
                    set: { styleStore.style.accent = $0 }
                ))
            }

            HStack {
                Spacer()
                Button(loc("重置样式", "Reset Style")) { styleStore.reset() }
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var backgroundEditors: some View {
        switch styleStore.style.background {
        case .theme:
            Text("背景/明暗随主窗口主题自动变化。")
                .font(.caption)
                .foregroundColor(.secondary)
        case .material(let opacity):
            slider(loc("材质不透明度", "Material Opacity"), value: Binding(
                get: { opacity },
                set: { styleStore.style.background = .material(opacity: $0) }
            ), in: 0.3...1, step: 0.05)
        case .solid(let color):
            colorRow(loc("颜色", "Color"), color: Binding(
                get: { color },
                set: { styleStore.style.background = .solid($0) }
            ))
        case .gradient(let from, let to, let angle):
            colorRow(loc("起始色", "From"), color: Binding(
                get: { from },
                set: { styleStore.style.background = .gradient($0, to, angleDegrees: angle) }
            ))
            colorRow(loc("结束色", "To"), color: Binding(
                get: { to },
                set: { styleStore.style.background = .gradient(from, $0, angleDegrees: angle) }
            ))
            slider(loc("角度", "Angle"), value: Binding(
                get: { angle },
                set: { styleStore.style.background = .gradient(from, to, angleDegrees: $0) }
            ), in: 0...360, step: 15)
        }
    }

    private func slider(
        _ label: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .frame(width: 96, alignment: .leading)
            Slider(value: value, in: range, step: step)
        }
    }

    private func colorRow(_ label: String, color: Binding<RGBAColor>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .frame(width: 96, alignment: .leading)
            ColorPicker("", selection: Binding(
                get: { color.wrappedValue.color },
                set: { color.wrappedValue = RGBAColor(color: $0) }
            ), supportsOpacity: true)
            .labelsHidden()
            Spacer()
        }
    }
}

// MARK: - Quicklinks

struct LauncherQuicklinkSettings: View {
    @ObservedObject var store: QuicklinkStore
    @State private var newName = ""
    @State private var newTemplate = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quicklinks")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach(store.quicklinks) { quicklink in
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.caption)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(quicklink.name)
                            .font(.caption)
                        Text(quicklink.template)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        store.remove(id: quicklink.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                TextField("Name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(width: 80)
                TextField("URL template — use {query}", text: $newTemplate)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                Button("Add") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    let template = newTemplate.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty, !template.isEmpty else { return }
                    store.add(Quicklink(name: name, template: template))
                    newName = ""
                    newTemplate = ""
                }
                .font(.caption)
            }
        }
    }
}

// MARK: - Fallbacks

struct LauncherFallbackSettings: View {
    @ObservedObject var store: FallbackStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fallback Search")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach(Array(store.commands.enumerated()), id: \.element.id) { index, command in
                HStack(spacing: 6) {
                    Toggle("", isOn: Binding(
                        get: { command.enabled },
                        set: { store.setEnabled($0, id: command.id) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    Text(command.name)
                        .font(.caption)
                    Spacer()
                    Button {
                        guard index > 0 else { return }
                        store.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
                    } label: {
                        Image(systemName: "chevron.up").font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .disabled(index == 0)
                    Button {
                        guard index < store.commands.count - 1 else { return }
                        store.move(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
                    } label: {
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .disabled(index == store.commands.count - 1)
                }
            }
        }
    }
}

// MARK: - Alias & per-command hotkeys

struct LauncherAliasHotkeySettings: View {
    @ObservedObject var aliases: AliasStore
    @ObservedObject var hotkeys: CommandHotkeyStore
    let conflicts: [String: String]
    let rootItems: () -> [LauncherItem]

    @State private var selectedKey: String = ""
    @State private var aliasDraft: String = ""
    @State private var items: [LauncherItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Command Alias & Hotkey")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Picker("Command", selection: $selectedKey) {
                Text("Choose…").tag("")
                ForEach(items, id: \.id) { item in
                    Text("\(item.category) · \(item.title)").tag(item.id)
                }
            }
            .font(.caption)
            .onChange(of: selectedKey) { key in
                aliasDraft = aliases.alias(for: key) ?? ""
            }

            if !selectedKey.isEmpty {
                HStack(spacing: 6) {
                    TextField("Alias (e.g. gh)", text: $aliasDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Button("Save Alias") {
                        aliases.setAlias(aliasDraft, for: selectedKey)
                    }
                    .font(.caption)
                }

                KeyRecorderView { config in
                    hotkeys.set(config, for: selectedKey)
                }

                if hotkeys.hotkeys[selectedKey] != nil {
                    Button("Remove Hotkey") {
                        hotkeys.set(nil, for: selectedKey)
                    }
                    .font(.caption)
                }

                if let conflict = conflicts[selectedKey] {
                    Text(conflict)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            let assigned = aliases.aliases
            if !assigned.isEmpty {
                ForEach(assigned.sorted(by: { $0.key < $1.key }), id: \.key) { key, alias in
                    HStack(spacing: 6) {
                        Text(alias)
                            .font(.caption.monospaced())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                        Text(key)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            aliases.setAlias(nil, for: key)
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear {
            items = rootItems().sorted { $0.id < $1.id }
        }
    }
}

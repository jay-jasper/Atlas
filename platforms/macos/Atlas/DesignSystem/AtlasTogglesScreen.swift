import SwiftUI

/// Faithful recreation of the prototype's module selector (`Atlas Toggles.dc.html`):
/// header with count, search, filter pills, grouped module rows with status pills
/// and a custom on/off/locked switch, and footer.
struct AtlasTogglesScreen: View {
    @Environment(\.colorScheme) private var scheme
    var onBack: () -> Void = {}

    private struct Module: Identifiable {
        let id = UUID()
        let icon: String
        let name: String
        let key: String
        let desc: String
        var status: Status = .none
        var state: SwitchState
    }
    private enum Status { case none, running, paused, authorized, needPro, needPermission(String) }
    private enum SwitchState { case on, off, locked }
    private struct Group: Identifiable { let id = UUID(); let title: String; let count: String; let modules: [Module] }

    private let groups: [Group] = [
        Group(title: "监控与系统", count: "6 / 7", modules: [
            Module(icon: "chart.line.uptrend.xyaxis", name: "系统监控", key: "monitoring", desc: "CPU / 内存 / 网络 / 进程 实时统计", status: .running, state: .on),
            Module(icon: "network", name: "连接监控", key: "network", desc: "活动连接 · 按进程聚合", state: .on),
            Module(icon: "rectangle.split.2x2", name: "端口管理", key: "port-master", desc: "查询端口占用 · 一键结束进程", state: .on),
            Module(icon: "battery.75", name: "电池健康", key: "battery-health", desc: "充电 · 循环 · 健康度", status: .paused, state: .off),
            Module(icon: "wave.3.right", name: "蓝牙电量", key: "bluetooth-battery", desc: "显示已配对设备电量", state: .on),
            Module(icon: "cpu", name: "AI 负载监控", key: "ai-load", desc: "本地 LLM · 显存与活跃模型", status: .needPro, state: .locked),
        ]),
        Group(title: "音频", count: "3 / 5", modules: [
            Module(icon: "speaker.wave.2", name: "分应用音量", key: "app-audio", desc: "每个应用独立音量与静音", state: .on),
            Module(icon: "waveform", name: "麦克风电平", key: "level-meter", desc: "实时 VU · 峰值 dBFS", state: .on),
            Module(icon: "music.note", name: "Now Playing", key: "now-playing", desc: "媒体控制 · 曲名 / 进度", state: .on),
            Module(icon: "mic.slash", name: "降噪门", key: "noise-gate", desc: "麦克风阈值降噪", status: .needPermission("需麦克风权限"), state: .off),
            Module(icon: "circle.circle", name: "音频中枢", key: "audio-hub", desc: "输入 / 输出切换 · 设备预设", state: .off),
        ]),
        Group(title: "截图与录制", count: "5 / 10", modules: [
            Module(icon: "viewfinder", name: "截图工具", key: "screenshots", desc: "区域 / 窗口 / 滚动 / GIF · OCR · 标注", state: .on),
            Module(icon: "record.circle", name: "屏幕录制", key: "recording", desc: "桌面录像 · 摄像头叠加", status: .authorized, state: .on),
            Module(icon: "captions.bubble", name: "实时字幕", key: "live-caption", desc: "麦克风语音 → 大字幕条", status: .needPermission("需语音识别"), state: .locked),
            Module(icon: "text.alignleft", name: "本地转录", key: "transcription", desc: "Whisper · 音频 → 文本 / SRT", status: .needPro, state: .locked),
            Module(icon: "text.viewfinder", name: "提词器", key: "teleprompter", desc: "大字滚动 · 速度 / 镜像", state: .off),
        ]),
    ]

    var body: some View {
        let theme = AtlasTheme.resolve(for: scheme)
        AtlasPopupChrome {
            VStack(spacing: 0) {
                header(theme)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(groups) { group in
                            groupHeader(theme, group)
                            ForEach(group.modules) { moduleRow(theme, $0) }
                        }
                    }
                }
                footer(theme)
            }
        }
        .frame(width: 460, height: 720)
        .environment(\.atlasTheme, theme)
    }

    private func header(_ theme: AtlasTheme) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.text2).frame(width: 24, height: 24)
                        .background(theme.section, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Text("模块选配").font(.system(size: 15, weight: .semibold))
                Text("Feature Toggle Center").font(.system(size: 11)).foregroundStyle(theme.text3)
                Spacer(minLength: 0)
                AtlasPill(text: "已启用 23 / 64", tint: theme.accentText, background: theme.accentSoft)
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(theme.text3)
                Text("搜索模块名、能力或快捷键...").font(.system(size: 12)).foregroundStyle(theme.text3)
                Spacer(minLength: 0)
                Text("⌘F").font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.text3)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(theme.border, lineWidth: 1))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(theme.input, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.borderInput, lineWidth: 1))
            HStack(spacing: 5) {
                filterPill(theme, "全部", "64", selected: true)
                filterPill(theme, "已启用", "23", selected: false)
                filterPill(theme, "需 Pro", "8", selected: false)
                filterPill(theme, "需权限", "5", selected: false)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .overlay(Rectangle().fill(theme.divider).frame(height: 1), alignment: .bottom)
    }

    private func filterPill(_ theme: AtlasTheme, _ label: String, _ count: String, selected: Bool) -> some View {
        HStack(spacing: 4) {
            Text(label); Text(count).opacity(0.7)
        }
        .font(.system(size: 9.5, weight: .medium)).tracking(0.4)
        .foregroundStyle(selected ? theme.accentText : theme.text2)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(selected ? theme.accentSoft : .clear, in: Capsule())
        .overlay(Capsule().stroke(selected ? .clear : theme.border, lineWidth: 1))
    }

    private func groupHeader(_ theme: AtlasTheme, _ group: Group) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(theme.text3)
            Text(group.title.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.6).foregroundStyle(theme.text2)
            Spacer(minLength: 0)
            Text(group.count).font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.text3)
        }
        .padding(.horizontal, 14).padding(.top, 11).padding(.bottom, 5)
    }

    private func moduleRow(_ theme: AtlasTheme, _ module: Module) -> some View {
        HStack(spacing: 10) {
            Image(systemName: module.icon).font(.system(size: 11))
                .foregroundStyle(module.state == .on ? theme.accentText : theme.text2)
                .frame(width: 22, height: 22)
                .background(theme.section, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.divider, lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(module.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(theme.text1)
                    Text(module.key).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(theme.text3)
                }
                Text(module.desc).font(.system(size: 10.5)).foregroundStyle(theme.text3)
            }
            Spacer(minLength: 0)
            statusPill(theme, module.status)
            toggleSwitch(theme, module.state)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
    }

    @ViewBuilder
    private func statusPill(_ theme: AtlasTheme, _ status: Status) -> some View {
        switch status {
        case .none: EmptyView()
        case .running: miniPill(theme, "运行中", tint: theme.green, bg: theme.greenSoft)
        case .paused: miniPill(theme, "已暂停", tint: theme.text3, bg: theme.input)
        case .authorized: miniPill(theme, "已授权", tint: theme.green, bg: theme.greenSoft)
        case .needPro: miniPill(theme, "需 Pro", tint: theme.orange, bg: theme.orangeSoft)
        case .needPermission(let t): miniPill(theme, t, tint: theme.red, bg: theme.redSoft)
        }
    }

    private func miniPill(_ theme: AtlasTheme, _ text: String, tint: Color, bg: Color) -> some View {
        Text(text).font(.system(size: 9.5, weight: .semibold)).tracking(0.4)
            .foregroundStyle(tint).padding(.horizontal, 6).padding(.vertical, 1)
            .background(bg, in: Capsule())
    }

    private func toggleSwitch(_ theme: AtlasTheme, _ state: SwitchState) -> some View {
        let trackColor: Color = state == .on ? theme.accent : (state == .locked ? theme.input : theme.borderStrong)
        return ZStack(alignment: state == .on ? .trailing : .leading) {
            Capsule().fill(trackColor).frame(width: 30, height: 18)
            Circle().fill(.white).frame(width: 16, height: 16)
                .opacity(state == .locked ? 0.55 : 1)
                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                .padding(1)
        }
        .frame(width: 30, height: 18)
    }

    private func footer(_ theme: AtlasTheme) -> some View {
        HStack(spacing: 10) {
            (Text("本场景 ") + Text("Focus").foregroundColor(theme.text1).fontWeight(.medium) + Text(" 已配置 7 模块"))
                .foregroundStyle(theme.text3)
            Spacer(minLength: 0)
            Button("Scene 设置") {}.buttonStyle(.plain).foregroundStyle(theme.text2)
            Text("·").foregroundStyle(theme.borderStrong)
            Button("完成 ✓", action: onBack).buttonStyle(.plain).foregroundStyle(theme.accentText).fontWeight(.medium)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(theme.section)
        .overlay(Rectangle().fill(theme.divider).frame(height: 1), alignment: .top)
    }
}

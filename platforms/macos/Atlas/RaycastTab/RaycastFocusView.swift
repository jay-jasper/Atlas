import AppKit
import SwiftUI

/// 专注页:目标/时长/屏蔽 app/勿扰配置 + 运行态控制 + 历史。
struct RaycastFocusView: View {
    @ObservedObject private var service = FocusService.shared
    @State private var goal = ""
    @State private var minutes = 25.0
    @State private var blockedApps: [String] = UserDefaults.standard.stringArray(forKey: "focus.blocked") ?? []
    @State private var enableDND = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if service.isActive {
                activePanel
            } else {
                configPanel
            }
            historySection
        }
    }

    private var activePanel: some View {
        SettingsSection(title: loc("进行中", "In Session")) {
            VStack(spacing: 12) {
                Text(service.client.status.config?.goal ?? "")
                    .font(.system(size: 15, weight: .semibold))
                Text(service.remainingText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                HStack(spacing: 12) {
                    if service.client.status.phase == .paused {
                        Button(loc("继续", "Resume")) { service.resume() }
                    } else {
                        Button(loc("暂停", "Pause")) { service.pause() }
                    }
                    Button(loc("结束", "End"), role: .destructive) { service.stop() }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
    }

    private var configPanel: some View {
        SettingsSection(title: loc("开始专注", "Start Focus")) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(icon: "target", title: loc("目标", "Goal")) {
                    TextField(loc("这次要做什么?", "What are you working on?"), text: $goal)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
                SettingsRowDivider()
                SettingsRow(
                    icon: "clock",
                    title: loc("时长", "Duration"),
                    description: "\(Int(minutes)) min"
                ) {
                    Slider(value: $minutes, in: 5...120, step: 5)
                        .frame(width: 180)
                }
                SettingsRowDivider()
                SettingsRow(
                    icon: "nosign.app",
                    title: loc("屏蔽应用", "Blocked apps"),
                    description: blockedApps.isEmpty
                        ? loc("会话中打开这些 app 会被自动隐藏", "Apps auto-hide during a session")
                        : blockedApps.joined(separator: ", ")
                ) {
                    Button(loc("选择…", "Choose…")) { pickApps() }
                }
                SettingsRowDivider()
                SettingsRow(
                    icon: "moon",
                    title: loc("自动勿扰", "Auto DND"),
                    description: loc("需要名为 Atlas-DND-On/Off 的快捷指令", "Requires Shortcuts named Atlas-DND-On/Off")
                ) {
                    Toggle("", isOn: $enableDND).labelsHidden().toggleStyle(.switch)
                }
                SettingsRowDivider()
                HStack {
                    Spacer()
                    Button(loc("开始专注", "Start Focus")) {
                        service.start(
                            goal: goal.isEmpty ? loc("专注", "Focus") : goal,
                            minutes: UInt32(minutes),
                            blocked: blockedApps,
                            dnd: enableDND
                        )
                    }
                    .keyboardShortcut(.defaultAction)
                    Spacer()
                }
                .padding(.vertical, 10)
            }
        }
    }

    private var historySection: some View {
        SettingsSection(title: loc("历史", "History")) {
            let history = service.client.history.suffix(8).reversed()
            if history.isEmpty {
                SettingsRow(icon: "clock.arrow.circlepath", title: loc("暂无记录", "No sessions yet")) {
                    EmptyView()
                }
            } else {
                ForEach(Array(history.enumerated()), id: \.offset) { index, session in
                    SettingsRow(
                        icon: session.completed ? "checkmark.circle" : "xmark.circle",
                        tint: session.completed ? .green : .orange,
                        title: session.goal,
                        description: "\(session.durationMin) min · " + Self.dateText(session.startedAt)
                    ) { EmptyView() }
                    if index < history.count - 1 {
                        SettingsRowDivider()
                    }
                }
            }
        }
    }

    private static func dateText(_ epoch: UInt64) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }

    /// NSOpenPanel 选 .app,存 bundle id。
    private func pickApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        blockedApps = Array(Set(blockedApps + ids)).sorted()
        UserDefaults.standard.set(blockedApps, forKey: "focus.blocked")
    }
}

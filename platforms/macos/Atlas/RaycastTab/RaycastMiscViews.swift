import AppKit
import SwiftUI

// MARK: - 听写

struct RaycastDictationView: View {
    @ObservedObject private var service = DictationService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PermissionStatusSection(permissions: [.microphone, .speechRecognition])

            SettingsSection(title: loc("听写", "Dictation")) {
                VStack(spacing: 12) {
                    Text(service.transcript.isEmpty
                        ? loc("点击开始,实时转写显示在这里。", "Press start; live transcript appears here.")
                        : service.transcript)
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))

                    HStack(spacing: 12) {
                        if service.isRecording {
                            Button(loc("停止并复制", "Stop & Copy")) {
                                let text = service.stop()
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                            }
                            Button(loc("取消", "Cancel"), role: .destructive) { service.cancel() }
                        } else {
                            Button {
                                service.requestPermissions { granted in
                                    if granted { service.start() }
                                }
                            } label: {
                                Label(loc("开始听写", "Start Dictation"), systemImage: "mic.fill")
                            }
                        }
                    }

                    if let error = service.lastError {
                        Text(error).font(.caption).foregroundColor(.red)
                    }
                }
                .padding(12)
            }

            Text(loc("提示:启动台里也有「开始听写」命令,停止后自动粘贴到前台应用。",
                     "Tip: the launcher's Start Dictation command pastes into the frontmost app when stopped."))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 系统命令

struct RaycastSystemCommandsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(title: loc("系统命令", "System Commands")) {
                let commands = SystemCommandCatalog.commands
                ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                    SettingsRow(
                        icon: command.icon,
                        tint: command.needsConfirm ? .orange : .accentColor,
                        title: AppLanguage.current == .zh ? command.zh : command.en,
                        description: command.needsConfirm ? loc("执行前需确认", "Asks for confirmation") : nil
                    ) {
                        Button(loc("执行", "Run")) {
                            runWithConfirm(command)
                        }
                        .font(.caption)
                    }
                    if index < commands.count - 1 {
                        SettingsRowDivider()
                    }
                }
            }
            Text(loc("全部命令都可在启动台直接搜索执行。", "All commands are searchable from the launcher."))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func runWithConfirm(_ command: SystemCommandCatalog.Command) {
        if command.needsConfirm {
            let alert = NSAlert()
            alert.messageText = loc("确认\(command.zh)?", "Confirm \(command.en)?")
            alert.addButton(withTitle: loc("确定", "OK"))
            alert.addButton(withTitle: loc("取消", "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        SystemCommandCatalog.run(command)
    }
}

// MARK: - 日历

struct RaycastCalendarView: View {
    @State private var events: [(title: String, start: Date, meeting: URL?, eventID: String)] = []
    private let provider = CalendarEventsProvider()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PermissionStatusSection(permissions: [.calendar])

            SettingsSection(title: loc("未来 7 天", "Next 7 Days")) {
                let commands = provider.results(for: "")
                if commands.isEmpty {
                    SettingsRow(
                        icon: "calendar",
                        title: loc("无日程或未授权", "No events or not authorized"),
                        description: loc("授权日历后,事件可在启动台搜索,会议一键加入。",
                                         "Once authorized, events are searchable and meetings join in one tap.")
                    ) { EmptyView() }
                } else {
                    ForEach(Array(commands.enumerated()), id: \.offset) { index, command in
                        SettingsRow(
                            icon: "calendar",
                            title: command.title,
                            description: command.subtitle
                        ) { EmptyView() }
                        if index < commands.count - 1 {
                            SettingsRowDivider()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Hyper Key

struct RaycastHyperKeyView: View {
    @ObservedObject private var service = HyperKeyService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PermissionStatusSection(permissions: [.accessibility])

            SettingsSection(title: "Hyper Key") {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsRow(
                        icon: "keyboard",
                        title: loc("启用 Hyper Key", "Enable Hyper Key"),
                        description: loc("按住触发键 + 任意键 = ⌘⌥⌃⇧ 组合", "Hold trigger + any key = ⌘⌥⌃⇧ combo")
                    ) {
                        Toggle("", isOn: $service.isEnabled).labelsHidden().toggleStyle(.switch)
                    }
                    SettingsRowDivider()
                    SettingsRow(icon: "command", title: loc("触发键", "Trigger key")) {
                        Picker("", selection: $service.trigger) {
                            ForEach(HyperKeyService.TriggerKey.allCases) { key in
                                Text(key.display).tag(key)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    SettingsRowDivider()
                    SettingsRow(
                        icon: "hand.tap",
                        title: loc("单击行为", "Tap behavior"),
                        description: loc("快速按下松开(无组合)时执行", "When tapped without combining")
                    ) {
                        Picker("", selection: $service.tapBehavior) {
                            ForEach(HyperKeyService.TapBehavior.allCases) { behavior in
                                Text(behavior.display).tag(behavior)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }
            }

            Text(loc("提示:CapsLock 作触发键时大写锁定被接管;想恢复原功能请停用。",
                     "Note: with CapsLock as trigger the caps toggle is taken over; disable to restore."))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

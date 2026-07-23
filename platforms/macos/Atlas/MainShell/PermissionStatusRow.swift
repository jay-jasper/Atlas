import ApplicationServices
import AVFoundation
import CoreGraphics
import EventKit
import Speech
import SwiftUI

/// 工具设置页顶部的权限状态区(MacTools 插件设置页同构)。
enum ToolPermission: String, CaseIterable {
    case accessibility
    case screenRecording
    case microphone
    case speechRecognition
    case calendar

    var title: String {
        switch self {
        case .accessibility: return "辅助功能授权"
        case .screenRecording: return "屏幕录制授权"
        case .microphone: return "麦克风授权"
        case .speechRecognition: return "语音识别授权"
        case .calendar: return "日历授权"
        }
    }

    var explanation: String {
        switch self {
        case .accessibility:
            return "前往 系统设置 → 隐私与安全性 → 辅助功能,授权 Atlas。"
        case .screenRecording:
            return "前往 系统设置 → 隐私与安全性 → 屏幕录制,授权 Atlas。"
        case .microphone:
            return "前往 系统设置 → 隐私与安全性 → 麦克风,授权 Atlas。"
        case .speechRecognition:
            return "前往 系统设置 → 隐私与安全性 → 语音识别,授权 Atlas。"
        case .calendar:
            return "前往 系统设置 → 隐私与安全性 → 日历,授权 Atlas 完全访问。"
        }
    }

    var settingsURL: URL {
        switch self {
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        case .speechRecognition:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!
        case .calendar:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
        }
    }

    var isGranted: Bool {
        switch self {
        case .accessibility: return AXIsProcessTrusted()
        case .screenRecording: return CGPreflightScreenCaptureAccess()
        case .microphone: return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .speechRecognition: return SFSpeechRecognizer.authorizationStatus() == .authorized
        case .calendar:
            if #available(macOS 14.0, *) {
                return EKEventStore.authorizationStatus(for: .event) == .fullAccess
            }
            return EKEventStore.authorizationStatus(for: .event) == .authorized
        }
    }
}

struct PermissionStatusSection: View {
    let permissions: [ToolPermission]
    @State private var refreshTick = 0

    var body: some View {
        if !permissions.isEmpty {
            SettingsSection(title: "权限") {
                ForEach(Array(permissions.enumerated()), id: \.element) { index, permission in
                    let granted = permission.isGranted
                    let _ = refreshTick // re-evaluate on tick
                    SettingsRow(
                        icon: granted ? "checkmark.shield" : "exclamationmark.shield",
                        tint: granted ? .green : .orange,
                        title: permission.title + (granted ? "" : " · 未授权"),
                        description: granted ? "已授权。" : permission.explanation
                    ) {
                        if !granted {
                            Button("前往授权") {
                                NSWorkspace.shared.open(permission.settingsURL)
                            }
                            .font(.callout)
                        }
                    }
                    if index < permissions.count - 1 {
                        SettingsRowDivider()
                    }
                }
            }
            .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
                refreshTick += 1
            }
        }
    }
}

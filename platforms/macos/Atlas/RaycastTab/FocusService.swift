import AppKit
import Foundation
import UserNotifications

/// 专注会话执行层:Rust 状态机 + Swift 屏蔽/通知/勿扰。
@MainActor
final class FocusService: ObservableObject {
    static let shared = FocusService()

    let client = FocusClient()
    @Published private(set) var remainingText: String = ""
    @Published private(set) var isActive = false

    private var timer: Timer?
    private var notifiedCompletion = false

    init() {
        syncFromState()
    }

    func start(goal: String, minutes: UInt32, blocked: [String], dnd: Bool) {
        guard client.start(goal: goal, minutes: minutes, blocked: blocked, dnd: dnd) else { return }
        notifiedCompletion = false
        if dnd { setDND(true) }
        syncFromState()
    }

    func pause() { client.pause(); syncFromState() }
    func resume() { client.resume(); syncFromState() }

    func stop() {
        let dnd = client.status.config?.enableDnd ?? false
        client.stop()
        if dnd { setDND(false) }
        syncFromState()
    }

    /// 每秒 tick:倒计时 + 屏蔽 + 到时收尾。
    private func tick() {
        client.refresh()
        let status = client.status
        switch status.phase {
        case .running:
            isActive = true
            remainingText = Self.format(seconds: status.remainingSecs)
            enforceBlocklist(status.config?.blockedBundleIds ?? [])
        case .paused:
            isActive = true
            remainingText = "⏸ " + Self.format(seconds: status.remainingSecs)
        case .idle:
            // Running → Idle 过渡即到时完成(手动 stop 走 stop())。
            if isActive, !notifiedCompletion {
                notifiedCompletion = true
                notifyCompletion()
                if clientHadDND { setDND(false) }
            }
            isActive = false
            remainingText = ""
        }
        scheduleOrCancelTimer()
    }

    private var clientHadDND = false

    private func syncFromState() {
        clientHadDND = client.status.config?.enableDnd ?? false
        tick()
    }

    private func scheduleOrCancelTimer() {
        if isActive, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } else if !isActive {
            timer?.invalidate()
            timer = nil
        }
    }

    private func enforceBlocklist(_ bundleIDs: [String]) {
        guard !bundleIDs.isEmpty,
              let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontmost.bundleIdentifier,
              bundleIDs.contains(bundleID)
        else { return }
        frontmost.hide()
    }

    private func notifyCompletion() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = loc("专注完成", "Focus complete")
            content.body = loc("本次专注已结束,休息一下吧。", "Session finished — take a break.")
            content.sound = .default
            center.add(UNNotificationRequest(
                identifier: "focus-complete-\(UUID().uuidString)",
                content: content,
                trigger: nil
            ))
        }
        NSSound(named: "Glass")?.play()
    }

    /// 勿扰:macOS 无公开 API,走 Shortcuts CLI(用户需有"Set Focus"类快捷指令);
    /// 失败静默跳过(spec 决策)。
    private func setDND(_ on: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", on ? "Atlas-DND-On" : "Atlas-DND-Off"]
        try? process.run()
    }

    nonisolated static func format(seconds: UInt64) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

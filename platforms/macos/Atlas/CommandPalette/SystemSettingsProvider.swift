import AppKit
import Foundation

/// 系统设置面板搜索(rubick 思路的 macOS 13+ 版):内置面板清单,
/// 中英文名直搜、拼音由引擎兜底,命中后 URL scheme 直达对应面板。
final class SystemSettingsProvider: CommandProviding {
    struct Pane {
        let zh: String
        let en: String
        let target: String   // x-apple.systempreferences target
    }

    static let panes: [Pane] = [
        Pane(zh: "无线局域网", en: "Wi-Fi", target: "com.apple.wifi-settings-extension"),
        Pane(zh: "蓝牙", en: "Bluetooth", target: "com.apple.BluetoothSettings"),
        Pane(zh: "网络", en: "Network", target: "com.apple.Network-Settings.extension"),
        Pane(zh: "通知", en: "Notifications", target: "com.apple.Notifications-Settings.extension"),
        Pane(zh: "声音", en: "Sound", target: "com.apple.Sound-Settings.extension"),
        Pane(zh: "专注模式", en: "Focus", target: "com.apple.Focus-Settings.extension"),
        Pane(zh: "屏幕使用时间", en: "Screen Time", target: "com.apple.Screen-Time-Settings.extension"),
        Pane(zh: "通用", en: "General", target: "com.apple.systempreferences.GeneralSettings"),
        Pane(zh: "外观", en: "Appearance", target: "com.apple.Appearance-Settings.extension"),
        Pane(zh: "辅助功能", en: "Accessibility", target: "com.apple.Accessibility-Settings.extension"),
        Pane(zh: "控制中心", en: "Control Center", target: "com.apple.ControlCenter-Settings.extension"),
        Pane(zh: "Siri 与聚焦", en: "Siri & Spotlight", target: "com.apple.Siri-Settings.extension"),
        Pane(zh: "隐私与安全性", en: "Privacy & Security", target: "com.apple.settings.PrivacySecurity.extension"),
        Pane(zh: "桌面与程序坞", en: "Desktop & Dock", target: "com.apple.Desktop-Settings.extension"),
        Pane(zh: "显示器", en: "Displays", target: "com.apple.Displays-Settings.extension"),
        Pane(zh: "墙纸", en: "Wallpaper", target: "com.apple.Wallpaper-Settings.extension"),
        Pane(zh: "屏幕保护程序", en: "Screen Saver", target: "com.apple.ScreenSaver-Settings.extension"),
        Pane(zh: "电池", en: "Battery", target: "com.apple.Battery-Settings.extension"),
        Pane(zh: "锁定屏幕", en: "Lock Screen", target: "com.apple.Lock-Screen-Settings.extension"),
        Pane(zh: "触控 ID 与密码", en: "Touch ID & Password", target: "com.apple.Touch-ID-Settings.extension"),
        Pane(zh: "用户与群组", en: "Users & Groups", target: "com.apple.Users-Groups-Settings.extension"),
        Pane(zh: "密码", en: "Passwords", target: "com.apple.Passwords-Settings.extension"),
        Pane(zh: "互联网账户", en: "Internet Accounts", target: "com.apple.Internet-Accounts-Settings.extension"),
        Pane(zh: "钱包与 Apple Pay", en: "Wallet & Apple Pay", target: "com.apple.WalletSettingsExtension"),
        Pane(zh: "键盘", en: "Keyboard", target: "com.apple.Keyboard-Settings.extension"),
        Pane(zh: "鼠标", en: "Mouse", target: "com.apple.Mouse-Settings.extension"),
        Pane(zh: "触控板", en: "Trackpad", target: "com.apple.Trackpad-Settings.extension"),
        Pane(zh: "打印机与扫描仪", en: "Printers & Scanners", target: "com.apple.Print-Scan-Settings.extension"),
        Pane(zh: "游戏中心", en: "Game Center", target: "com.apple.Game-Center-Settings.extension"),
        Pane(zh: "软件更新", en: "Software Update", target: "com.apple.Software-Update-Settings.extension"),
        Pane(zh: "存储空间", en: "Storage", target: "com.apple.settings.Storage"),
        Pane(zh: "时间机器", en: "Time Machine", target: "com.apple.Time-Machine-Settings.extension"),
        Pane(zh: "日期与时间", en: "Date & Time", target: "com.apple.Date-Time-Settings.extension"),
        Pane(zh: "共享", en: "Sharing", target: "com.apple.Sharing-Settings.extension"),
        Pane(zh: "启动磁盘", en: "Startup Disk", target: "com.apple.Startup-Disk-Settings.extension"),
        Pane(zh: "地区与语言", en: "Language & Region", target: "com.apple.Localization-Settings.extension"),
    ]

    private let openTarget: (String) -> Void

    init(openTarget: @escaping (String) -> Void = { target in
        if let url = URL(string: "x-apple.systempreferences:\(target)") {
            NSWorkspace.shared.open(url)
        }
    }) {
        self.openTarget = openTarget
    }

    private lazy var commands: [PaletteCommand] = Self.panes.map { pane in
        let isChineseUI = AppLanguage.current == .zh
        let title = isChineseUI ? "\(pane.zh)设置" : "\(pane.en) Settings"
        return PaletteCommand(
            id: UUID(),
            title: title,
            subtitle: isChineseUI ? "系统设置 · \(pane.en)" : "System Settings · \(pane.zh)",
            icon: .sfSymbol("gearshape.2"),
            keywords: [pane.zh, pane.en, "系统设置", "system settings", "设置", "偏好"],
            action: .execute { [openTarget] in openTarget(pane.target) },
            category: isChineseUI ? "系统设置" : "System Settings"
        )
    }

    func results(for query: String) -> [PaletteCommand] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return commands }
        return commands.filter { cmd in
            cmd.title.localizedCaseInsensitiveContains(q)
                || cmd.keywords.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }
}

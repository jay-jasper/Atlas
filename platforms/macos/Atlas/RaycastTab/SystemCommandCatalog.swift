import AppKit
import Foundation

/// Raycast System Commands 全套:睡眠/锁屏/注销/重启/关机/废纸篓/
/// 深浅色/静音/音量/屏保/隐藏其他/推出磁盘。runner 注入可测。
struct SystemCommandCatalog {
    struct Command {
        let id: String
        let zh: String
        let en: String
        let icon: String
        let keywords: [String]
        /// 危险命令(重启/关机/注销)执行前确认。
        let needsConfirm: Bool
        let script: Script
    }

    enum Script {
        case appleScript(String)
        case shell(executable: String, args: [String])
    }

    static let commands: [Command] = [
        Command(id: "sys-sleep", zh: "睡眠", en: "Sleep", icon: "moon.zzz",
                keywords: ["sleep", "睡眠", "休眠", "shuimian"], needsConfirm: false,
                script: .appleScript("tell application \"System Events\" to sleep")),
        Command(id: "sys-lock", zh: "锁定屏幕", en: "Lock Screen", icon: "lock",
                keywords: ["lock", "锁屏", "锁定", "suoping"], needsConfirm: false,
                script: .shell(executable: "/usr/bin/pmset", args: ["displaysleepnow"])),
        Command(id: "sys-logout", zh: "注销", en: "Log Out", icon: "rectangle.portrait.and.arrow.right",
                keywords: ["logout", "注销", "登出"], needsConfirm: true,
                script: .appleScript("tell application \"System Events\" to log out")),
        Command(id: "sys-restart", zh: "重启", en: "Restart", icon: "arrow.clockwise.circle",
                keywords: ["restart", "reboot", "重启"], needsConfirm: true,
                script: .appleScript("tell application \"System Events\" to restart")),
        Command(id: "sys-shutdown", zh: "关机", en: "Shut Down", icon: "power",
                keywords: ["shutdown", "关机"], needsConfirm: true,
                script: .appleScript("tell application \"System Events\" to shut down")),
        Command(id: "sys-empty-trash", zh: "清空废纸篓", en: "Empty Trash", icon: "trash",
                keywords: ["trash", "废纸篓", "垃圾", "清空"], needsConfirm: true,
                script: .appleScript("tell application \"Finder\" to empty trash")),
        Command(id: "sys-toggle-appearance", zh: "切换深浅色", en: "Toggle Dark Mode", icon: "circle.lefthalf.filled",
                keywords: ["dark", "light", "深色", "浅色", "暗色", "外观"], needsConfirm: false,
                script: .appleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")),
        Command(id: "sys-mute", zh: "静音切换", en: "Toggle Mute", icon: "speaker.slash",
                keywords: ["mute", "静音"], needsConfirm: false,
                script: .appleScript("set volume output muted (not (output muted of (get volume settings)))")),
        Command(id: "sys-volume-up", zh: "音量 +", en: "Volume Up", icon: "speaker.wave.3",
                keywords: ["volume", "音量"], needsConfirm: false,
                script: .appleScript("set volume output volume ((output volume of (get volume settings)) + 10)")),
        Command(id: "sys-volume-down", zh: "音量 -", en: "Volume Down", icon: "speaker.wave.1",
                keywords: ["volume", "音量"], needsConfirm: false,
                script: .appleScript("set volume output volume ((output volume of (get volume settings)) - 10)")),
        Command(id: "sys-screensaver", zh: "启动屏保", en: "Start Screen Saver", icon: "sparkles.tv",
                keywords: ["screensaver", "屏保"], needsConfirm: false,
                script: .shell(executable: "/usr/bin/open", args: ["-a", "ScreenSaverEngine"])),
        Command(id: "sys-hide-others", zh: "隐藏其他应用", en: "Hide Others", icon: "eye.slash",
                keywords: ["hide", "隐藏"], needsConfirm: false,
                script: .appleScript("tell application \"System Events\" to set visible of (every process whose frontmost is false and background only is false) to false")),
        Command(id: "sys-eject-disks", zh: "推出所有磁盘", en: "Eject All Disks", icon: "eject",
                keywords: ["eject", "推出", "磁盘"], needsConfirm: false,
                script: .appleScript("tell application \"Finder\" to eject (every disk whose ejectable is true)")),
    ]

    /// 执行入口;appleScript 走 NSAppleScript,shell 走注入 runner。
    static func run(
        _ command: Command,
        runner: SystemCommandRunning = LiveSystemCommandRunner(),
        appleScriptRunner: (String) -> Void = { source in
            DispatchQueue.global(qos: .userInitiated).async {
                NSAppleScript(source: source)?.executeAndReturnError(nil)
            }
        }
    ) {
        switch command.script {
        case .appleScript(let source):
            appleScriptRunner(source)
        case .shell(let executable, let args):
            _ = try? runner.run(executable, arguments: args)
        }
    }
}

/// 启动台 provider:全部系统命令一条一行(需确认的先弹确认)。
final class SystemCommandsProvider: CommandProviding {
    private let execute: (SystemCommandCatalog.Command) -> Void

    init(execute: @escaping (SystemCommandCatalog.Command) -> Void = { command in
        if command.needsConfirm {
            let alert = NSAlert()
            alert.messageText = loc("确认\(command.zh)?", "Confirm \(command.en)?")
            alert.addButton(withTitle: loc("确定", "OK"))
            alert.addButton(withTitle: loc("取消", "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        SystemCommandCatalog.run(command)
    }) {
        self.execute = execute
    }

    private lazy var commands: [PaletteCommand] = SystemCommandCatalog.commands.map { command in
        let isChineseUI = AppLanguage.current == .zh
        return PaletteCommand(
            id: UUID(),
            title: isChineseUI ? command.zh : command.en,
            subtitle: isChineseUI ? "系统命令 · \(command.en)" : "System Command",
            icon: .sfSymbol(command.icon),
            keywords: command.keywords + ["system", "系统命令"],
            action: .execute { [execute] in execute(command) },
            category: isChineseUI ? "系统命令" : "System Commands"
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

import Foundation

@MainActor
final class QuickSwitchService: ObservableObject {
    @Published private(set) var states: [QuickSwitchID: Bool] = [:]
    @Published private(set) var statusMessage: String = ""

    private let runner: SystemCommandRunning
    /// Keep Awake is handled in-process; this hook lets the app wire it up.
    var onKeepAwakeChanged: ((Bool) -> Void)?

    init(runner: SystemCommandRunning = LiveSystemCommandRunner()) {
        self.runner = runner
        for id in QuickSwitchID.allCases { states[id] = false }
    }

    func isOn(_ id: QuickSwitchID) -> Bool { states[id] ?? false }

    func toggle(_ id: QuickSwitchID) {
        set(id, on: !isOn(id))
    }

    func set(_ id: QuickSwitchID, on: Bool) {
        if id == .keepAwake {
            states[id] = on
            onKeepAwakeChanged?(on)
            return
        }
        let command = QuickSwitchCommandBuilder.setCommand(id, on: on)
        do {
            _ = try runner.run(command.executable, arguments: command.arguments)
            states[id] = on
            statusMessage = ""
        } catch {
            statusMessage = "\(id.title) requires a helper (e.g. blueutil/Shortcuts)."
        }
    }
}

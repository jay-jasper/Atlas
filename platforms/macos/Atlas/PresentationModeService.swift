import Foundation

final class PresentationModeService: ObservableObject {
    @Published private(set) var status: SystemUtilityStatus = .idle

    private let commandRunner: SystemCommandRunning
    private let keepAwakeService: KeepAwakeService
    private let toggleNotificationFocusScript = "tell application \"System Events\" to tell process \"Control Center\" to key code 113 using {option down}"

    init(
        commandRunner: SystemCommandRunning = LiveSystemCommandRunner(),
        keepAwakeService: KeepAwakeService
    ) {
        self.commandRunner = commandRunner
        self.keepAwakeService = keepAwakeService
    }

    func start() throws {
        do {
            try keepAwakeService.start()
            let result = try commandRunner.run("/usr/bin/osascript", arguments: ["-e", toggleNotificationFocusScript])
            guard result.succeeded else {
                let message = result.standardError.isEmpty ? "Unable to toggle notification focus" : result.standardError
                status = .failed(message)
                keepAwakeService.stop()
                throw PresentationModeError.commandFailed(message)
            }
            status = .running
        } catch {
            if case .failed = status {
            } else {
                status = .failed(error.localizedDescription)
            }
            keepAwakeService.stop()
            throw error
        }
    }

    func stop() {
        _ = try? commandRunner.run("/usr/bin/osascript", arguments: ["-e", toggleNotificationFocusScript])
        keepAwakeService.stop()
        status = .idle
    }
}

enum PresentationModeError: Error, Equatable {
    case commandFailed(String)
}

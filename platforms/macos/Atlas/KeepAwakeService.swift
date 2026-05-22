import Foundation

final class KeepAwakeService: ObservableObject {
    @Published private(set) var status: SystemUtilityStatus = .idle

    private let commandRunner: SystemCommandRunning
    private var process: SystemCommandProcess?

    init(commandRunner: SystemCommandRunning = LiveSystemCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func start() throws {
        if process?.isRunning == true {
            status = .running
            return
        }

        do {
            process = try commandRunner.start("/usr/bin/caffeinate", arguments: ["-dimsu"])
            status = .running
        } catch {
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        status = .idle
    }
}

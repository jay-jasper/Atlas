import Foundation

protocol DisplayCapabilityProbing {
    func probe() throws -> SystemCommandResult
}

struct LiveDisplayCapabilityProbe: DisplayCapabilityProbing {
    private let commandRunner: SystemCommandRunning

    init(commandRunner: SystemCommandRunning = LiveSystemCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func probe() throws -> SystemCommandResult {
        try commandRunner.run("/usr/bin/env", arguments: ["ddcctl", "-d", "1", "-b", "?"])
    }
}

final class DisplayControlService: ObservableObject {
    @Published private(set) var displays: [DisplayDevice] = []
    @Published private(set) var status: SystemUtilityStatus = .idle

    private let probe: DisplayCapabilityProbing

    init(probe: DisplayCapabilityProbing = LiveDisplayCapabilityProbe()) {
        self.probe = probe
    }

    @discardableResult
    func refreshDisplays() throws -> [DisplayDevice] {
        let result = try probe.probe()
        guard result.succeeded else {
            let message = result.standardError.isEmpty ? "Display control probe failed" : result.standardError
            displays = []
            status = .unavailable(message)
            throw DisplayControlError.probeFailed(message)
        }

        displays = DisplayControlParser.parse(result.standardOutput)
        status = displays.isEmpty ? .unavailable("No controllable displays detected") : .idle
        return displays
    }
}

enum DisplayControlError: Error, Equatable {
    case probeFailed(String)
}

enum DisplayControlParser {
    static func parse(_ output: String) -> [DisplayDevice] {
        output
            .split(separator: "\n")
            .enumerated()
            .compactMap { index, line in
                let text = String(line)
                guard text.hasPrefix("Display ") else {
                    return nil
                }

                let components = text.split(separator: ":", maxSplits: 1).map(String.init)
                guard components.count == 2 else {
                    return nil
                }

                let rawName = components[1]
                    .replacingOccurrences(of: "DDC/CI supported", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let isBuiltin = rawName.localizedCaseInsensitiveContains("built-in")
                let supportsDDC = text.localizedCaseInsensitiveContains("DDC/CI supported")

                return DisplayDevice(
                    id: "display-\(index + 1)",
                    name: rawName,
                    isBuiltin: isBuiltin,
                    supportsDDC: supportsDDC
                )
            }
    }
}

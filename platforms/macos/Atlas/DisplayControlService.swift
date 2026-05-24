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
    @Published var brightnessLevels: [String: Int] = [:]

    private let probe: DisplayCapabilityProbing
    private let commandRunner: SystemCommandRunning

    init(
        probe: DisplayCapabilityProbing = LiveDisplayCapabilityProbe(),
        commandRunner: SystemCommandRunning = LiveSystemCommandRunner()
    ) {
        self.probe = probe
        self.commandRunner = commandRunner
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

    func setBrightness(for display: DisplayDevice, to value: Int) {
        let clamped = max(0, min(100, value))
        brightnessLevels[display.id] = clamped
        let args = ["ddcctl", "-d", "\(display.ddcIndex)", "-b", "\(clamped)"]
        _ = try? commandRunner.run("/usr/bin/env", arguments: args)
    }

    func refreshBrightness(for display: DisplayDevice) {
        let args = ["ddcctl", "-d", "\(display.ddcIndex)", "-b", "?"]
        guard let result = try? commandRunner.run("/usr/bin/env", arguments: args),
              let value = DisplayControlParser.parseBrightness(result.standardOutput) else { return }
        brightnessLevels[display.id] = value
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
                guard text.hasPrefix("Display ") else { return nil }

                let components = text.split(separator: ":", maxSplits: 1).map(String.init)
                guard components.count == 2 else { return nil }

                let rawName = components[1]
                    .replacingOccurrences(of: "DDC/CI supported", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let isBuiltin = rawName.localizedCaseInsensitiveContains("built-in")
                let supportsDDC = text.localizedCaseInsensitiveContains("DDC/CI supported")

                return DisplayDevice(
                    id: "display-\(index + 1)",
                    name: rawName,
                    isBuiltin: isBuiltin,
                    supportsDDC: supportsDDC,
                    ddcIndex: index + 1
                )
            }
    }

    // Parses brightness from ddcctl output, e.g. "D: [10] brightness: 75" or "current=75"
    static func parseBrightness(_ output: String) -> Int? {
        let patterns = [
            #"brightness:\s*(\d+)"#,
            #"current=(\d+)"#,
            #"\bcurrent:\s*(\d+)"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
               let range = Range(match.range(at: 1), in: output),
               let value = Int(output[range]) {
                return value
            }
        }
        return nil
    }
}

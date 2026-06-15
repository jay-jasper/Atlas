import Foundation

@MainActor
final class PacketMonitorService: ObservableObject {
    @Published private(set) var traffic: [ProcessTraffic] = []
    @Published private(set) var statusMessage = ""

    private let runner: SystemCommandRunning

    init(runner: SystemCommandRunning = LiveSystemCommandRunner()) {
        self.runner = runner
    }

    func refresh() {
        guard let result = try? runner.run(
            "/usr/bin/nettop",
            arguments: ["-P", "-x", "-L", "1", "-J", "bytes_in,bytes_out"]
        ), result.succeeded else {
            statusMessage = "Could not read network stats."
            traffic = []
            return
        }
        traffic = PacketStatsParser.parse(result.standardOutput)
        statusMessage = traffic.isEmpty ? "No active network traffic." : ""
    }

    static func formatBytes(_ bytes: Int64) -> String {
        DiskUsageScanner.formatBytes(bytes)
    }
}

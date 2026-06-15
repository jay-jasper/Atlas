import Foundation
import SwiftUI

struct NetworkConnection: Identifiable, Equatable {
    let id: String
    let pid: Int
    let processName: String
    let localAddress: String
    let remoteAddress: String
    let state: String
    let proto: String

    var isEstablished: Bool { state == "ESTABLISHED" }
}

@MainActor
final class NetworkMonitorService: ObservableObject {
    @Published private(set) var connections: [NetworkConnection] = []
    @Published private(set) var status: String = ""
    @Published var filterText: String = ""

    private let commandRunner: SystemCommandRunning
    private var refreshTask: Task<Void, Never>?

    init(commandRunner: SystemCommandRunning = LiveSystemCommandRunner()) {
        self.commandRunner = commandRunner
    }

    var filteredConnections: [NetworkConnection] {
        guard !filterText.isEmpty else { return connections }
        let q = filterText.lowercased()
        return connections.filter {
            $0.processName.lowercased().contains(q) ||
            $0.remoteAddress.lowercased().contains(q)
        }
    }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { await fetchConnections() }
    }

    func startAutoRefresh(interval: TimeInterval = 5) {
        stopAutoRefresh()
        refreshTask = Task {
            while !Task.isCancelled {
                await fetchConnections()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func fetchConnections() async {
        guard let result = try? commandRunner.run(
            "/usr/sbin/lsof",
            arguments: ["-i", "-n", "-P", "-sTCP:ESTABLISHED"]
        ) else {
            status = "lsof failed"
            return
        }

        let parsed = NetworkMonitorParser.parse(result.standardOutput)
        connections = parsed
        status = parsed.isEmpty ? "No active outbound connections" : ""
    }
}

enum NetworkMonitorParser {
    static func parse(_ output: String) -> [NetworkConnection] {
        let lines = output.split(separator: "\n").dropFirst() // skip header
        var seen: Set<String> = []
        return lines.compactMap { line in
            let parts = String(line).split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            // lsof columns: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            guard parts.count >= 9 else { return nil }
            let command = parts[0]
            guard let pid = Int(parts[1]) else { return nil }
            let proto = parts[7].hasPrefix("IPv") ? parts[7] : "TCP"
            let name = parts[8]

            guard name.contains("->") else { return nil }
            let endpoints = name.split(separator: "->").map(String.init)
            guard endpoints.count == 2 else { return nil }

            let local = endpoints[0].trimmingCharacters(in: .whitespaces)
            let remote = endpoints[1].trimmingCharacters(in: .whitespaces)
            let stateField = (parts.count > 9 ? parts[9] : "ESTABLISHED")
                .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            let idKey = "\(pid)-\(local)-\(remote)"
            guard !seen.contains(idKey) else { return nil }
            seen.insert(idKey)

            return NetworkConnection(
                id: idKey,
                pid: pid,
                processName: command,
                localAddress: local,
                remoteAddress: remote,
                state: stateField,
                proto: proto
            )
        }
    }
}

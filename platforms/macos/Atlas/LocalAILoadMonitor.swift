import Foundation

protocol LocalAIAcceleratorSampling {
    func load(for provider: LocalAIProvider, processes: [LocalAIProcessSnapshot]) -> LocalAIAcceleratorLoad
}

struct BestEffortLocalAIAcceleratorSampler: LocalAIAcceleratorSampling {
    func load(for provider: LocalAIProvider, processes: [LocalAIProcessSnapshot]) -> LocalAIAcceleratorLoad {
        .unavailable
    }
}

struct LocalAILoadMonitor {
    let processSnapshotter: LocalAIProcessSnapshotting
    let acceleratorSampler: LocalAIAcceleratorSampling

    init(
        processSnapshotter: LocalAIProcessSnapshotting = LocalAIProcessSnapshotter(),
        acceleratorSampler: LocalAIAcceleratorSampling = BestEffortLocalAIAcceleratorSampler()
    ) {
        self.processSnapshotter = processSnapshotter
        self.acceleratorSampler = acceleratorSampler
    }

    func snapshot(now: Date = Date()) throws -> LocalAILoadSnapshot {
        let snapshots = try processSnapshotter.snapshots()
        let grouped = Dictionary(
            grouping: snapshots.compactMap { snapshot -> (LocalAIProvider, LocalAIProcessSnapshot)? in
                guard let provider = Self.provider(for: snapshot) else { return nil }
                return (provider, snapshot)
            },
            by: { $0.0 }
        )

        let providerOrder: [LocalAIProvider] = [.ollama, .lmStudio]
        let loads = providerOrder.compactMap { provider -> LocalAIProviderLoad? in
            guard grouped[provider] != nil else { return nil }
            let processes = grouped[provider, default: []].map(\.1)
            return LocalAIProviderLoad(
                provider: provider,
                processCount: processes.count,
                cpuPercent: processes.reduce(0) { $0 + $1.cpuPercent },
                residentMemoryBytes: processes.reduce(0) { $0 + $1.residentMemoryBytes },
                accelerator: acceleratorSampler.load(for: provider, processes: processes)
            )
        }

        return LocalAILoadSnapshot(providers: loads, capturedAt: now)
    }

    static func provider(for snapshot: LocalAIProcessSnapshot) -> LocalAIProvider? {
        let command = snapshot.command.lowercased()
        if command.contains("ollama") {
            return .ollama
        }

        if command.contains("lm studio") || command.contains("lmstudio") {
            return .lmStudio
        }

        return nil
    }
}

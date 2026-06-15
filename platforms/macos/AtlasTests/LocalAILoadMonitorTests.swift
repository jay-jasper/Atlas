import XCTest
@testable import Atlas

@MainActor
final class LocalAILoadMonitorTests: XCTestCase {
    func testDetectsOllamaAndLMStudioAndAggregatesCPUAndMemory() throws {
        let source = StaticLocalAIProcessSnapshotter(snapshots: [
            LocalAIProcessSnapshot(pid: 100, cpuPercent: 20.5, residentMemoryBytes: 1_000, command: "/Applications/Ollama.app/Contents/MacOS/Ollama serve"),
            LocalAIProcessSnapshot(pid: 101, cpuPercent: 5.0, residentMemoryBytes: 2_000, command: "ollama runner --model llama3"),
            LocalAIProcessSnapshot(pid: 200, cpuPercent: 10.0, residentMemoryBytes: 4_000, command: "/Applications/LM Studio.app/Contents/MacOS/LM Studio --server"),
            LocalAIProcessSnapshot(pid: 300, cpuPercent: 99.0, residentMemoryBytes: 8_000, command: "/usr/bin/OtherApp"),
        ])
        let monitor = LocalAILoadMonitor(
            processSnapshotter: source,
            acceleratorSampler: StaticLocalAIAcceleratorSampler(loads: [
                .ollama: LocalAIAcceleratorLoad(label: "Apple Neural Engine", utilizationPercent: nil, memoryBytes: nil),
            ])
        )

        let snapshot = try monitor.snapshot(now: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(snapshot.providers.count, 2)
        XCTAssertEqual(snapshot.providers[0], LocalAIProviderLoad(
            provider: .ollama,
            processCount: 2,
            cpuPercent: 25.5,
            residentMemoryBytes: 3_000,
            accelerator: LocalAIAcceleratorLoad(label: "Apple Neural Engine", utilizationPercent: nil, memoryBytes: nil)
        ))
        XCTAssertEqual(snapshot.providers[1], LocalAIProviderLoad(
            provider: .lmStudio,
            processCount: 1,
            cpuPercent: 10.0,
            residentMemoryBytes: 4_000,
            accelerator: .unavailable
        ))
    }
}

struct StaticLocalAIProcessSnapshotter: LocalAIProcessSnapshotting {
    let items: [LocalAIProcessSnapshot]

    init(snapshots: [LocalAIProcessSnapshot]) {
        self.items = snapshots
    }

    func snapshots() throws -> [LocalAIProcessSnapshot] {
        items
    }
}

struct StaticLocalAIAcceleratorSampler: LocalAIAcceleratorSampling {
    let loads: [LocalAIProvider: LocalAIAcceleratorLoad]

    func load(for provider: LocalAIProvider, processes: [LocalAIProcessSnapshot]) -> LocalAIAcceleratorLoad {
        loads[provider] ?? .unavailable
    }
}

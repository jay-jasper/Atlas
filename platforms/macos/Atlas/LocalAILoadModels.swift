import Foundation

enum LocalAIProvider: String, Equatable, Sendable {
    case ollama
    case lmStudio

    var title: String {
        switch self {
        case .ollama:
            return "Ollama"
        case .lmStudio:
            return "LM Studio"
        }
    }
}

struct LocalAIProcessSnapshot: Equatable, Sendable {
    let pid: Int
    let cpuPercent: Double
    let residentMemoryBytes: UInt64
    let command: String
}

struct LocalAIProviderLoad: Equatable, Identifiable, Sendable {
    var id: LocalAIProvider { provider }
    let provider: LocalAIProvider
    let processCount: Int
    let cpuPercent: Double
    let residentMemoryBytes: UInt64
    let accelerator: LocalAIAcceleratorLoad
}

struct LocalAIAcceleratorLoad: Equatable, Sendable {
    let label: String
    let utilizationPercent: Double?
    let memoryBytes: UInt64?

    static let unavailable = LocalAIAcceleratorLoad(
        label: "GPU/NPU unavailable",
        utilizationPercent: nil,
        memoryBytes: nil
    )
}

struct LocalAILoadSnapshot: Equatable, Sendable {
    let providers: [LocalAIProviderLoad]
    let capturedAt: Date

    static let empty = LocalAILoadSnapshot(providers: [], capturedAt: Date(timeIntervalSince1970: 0))
}

import Foundation

struct CommandUsageRecord: Codable, Equatable, Sendable {
    let commandKey: String
    var executionCount: Int
    var lastExecutedAt: Date
}

protocol CommandUsageRecording {
    func recordUsage(for command: PaletteCommand)
    func usageRecords() -> [String: CommandUsageRecord]
}

final class CommandUsageStore: CommandUsageRecording {
    private static let storageKey = "commandPalette.usageRecords"

    private let defaults: UserDefaults
    private let dateProvider: () -> Date
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        defaults: UserDefaults = .standard,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.dateProvider = dateProvider
    }

    func recordUsage(for command: PaletteCommand) {
        let key = Self.commandKey(for: command)
        var records = usageRecords()
        let now = dateProvider()

        if var record = records[key] {
            record.executionCount += 1
            record.lastExecutedAt = now
            records[key] = record
        } else {
            records[key] = CommandUsageRecord(
                commandKey: key,
                executionCount: 1,
                lastExecutedAt: now
            )
        }

        guard let data = try? encoder.encode(records) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func usageRecords() -> [String: CommandUsageRecord] {
        guard
            let data = defaults.data(forKey: Self.storageKey),
            let records = try? decoder.decode([String: CommandUsageRecord].self, from: data)
        else {
            return [:]
        }
        return records
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    static func commandKey(for command: PaletteCommand) -> String {
        "\(command.category)|\(command.title)"
    }
}

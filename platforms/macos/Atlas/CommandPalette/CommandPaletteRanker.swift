import Foundation

enum CommandPaletteRanker {
    static func ranked(
        _ commands: [PaletteCommand],
        records: [String: CommandUsageRecord]
    ) -> [PaletteCommand] {
        commands.enumerated()
            .sorted { lhs, rhs in
                let lhsRecord = records[CommandUsageStore.commandKey(for: lhs.element)]
                let rhsRecord = records[CommandUsageStore.commandKey(for: rhs.element)]
                let lhsCount = lhsRecord?.executionCount ?? 0
                let rhsCount = rhsRecord?.executionCount ?? 0

                if lhsCount != rhsCount {
                    return lhsCount > rhsCount
                }

                let lhsDate = lhsRecord?.lastExecutedAt ?? .distantPast
                let rhsDate = rhsRecord?.lastExecutedAt ?? .distantPast

                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }

                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

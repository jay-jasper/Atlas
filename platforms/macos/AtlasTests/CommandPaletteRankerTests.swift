import XCTest
@testable import Atlas

final class CommandPaletteRankerTests: XCTestCase {
    func testHigherExecutionCountRanksFirst() {
        let lowUsage = makeCommand(title: "Low Usage")
        let highUsage = makeCommand(title: "High Usage")

        let ranked = CommandPaletteRanker.ranked(
            [lowUsage, highUsage],
            records: [
                commandKey(for: lowUsage): makeRecord(for: lowUsage, count: 1, lastExecutedAt: Date(timeIntervalSince1970: 200)),
                commandKey(for: highUsage): makeRecord(for: highUsage, count: 3, lastExecutedAt: Date(timeIntervalSince1970: 100)),
            ]
        )

        XCTAssertEqual(ranked.map(\.title), ["High Usage", "Low Usage"])
    }

    func testMoreRecentRecordBreaksEqualCountTie() {
        let older = makeCommand(title: "Older")
        let newer = makeCommand(title: "Newer")

        let ranked = CommandPaletteRanker.ranked(
            [older, newer],
            records: [
                commandKey(for: older): makeRecord(for: older, count: 2, lastExecutedAt: Date(timeIntervalSince1970: 100)),
                commandKey(for: newer): makeRecord(for: newer, count: 2, lastExecutedAt: Date(timeIntervalSince1970: 200)),
            ]
        )

        XCTAssertEqual(ranked.map(\.title), ["Newer", "Older"])
    }

    func testRecordedCommandRanksBeforeUnrecordedCommand() {
        let unrecorded = makeCommand(title: "Unrecorded")
        let recorded = makeCommand(title: "Recorded")

        let ranked = CommandPaletteRanker.ranked(
            [unrecorded, recorded],
            records: [
                commandKey(for: recorded): makeRecord(for: recorded, count: 1, lastExecutedAt: Date(timeIntervalSince1970: 100)),
            ]
        )

        XCTAssertEqual(ranked.map(\.title), ["Recorded", "Unrecorded"])
    }

    func testUnrecordedCommandsKeepOriginalOrder() {
        let first = makeCommand(title: "First")
        let second = makeCommand(title: "Second")
        let third = makeCommand(title: "Third")

        let ranked = CommandPaletteRanker.ranked([first, second, third], records: [:])

        XCTAssertEqual(ranked.map(\.title), ["First", "Second", "Third"])
    }

    func testCommandsWithEqualUsageKeepOriginalOrder() {
        let first = makeCommand(title: "First")
        let second = makeCommand(title: "Second")
        let date = Date(timeIntervalSince1970: 100)

        let ranked = CommandPaletteRanker.ranked(
            [first, second],
            records: [
                commandKey(for: first): makeRecord(for: first, count: 2, lastExecutedAt: date),
                commandKey(for: second): makeRecord(for: second, count: 2, lastExecutedAt: date),
            ]
        )

        XCTAssertEqual(ranked.map(\.title), ["First", "Second"])
    }

    private func makeCommand(
        title: String,
        category: String = "Atlas"
    ) -> PaletteCommand {
        PaletteCommand(
            id: UUID(),
            title: title,
            subtitle: nil,
            icon: .sfSymbol("command"),
            keywords: [],
            action: .execute({}),
            category: category
        )
    }

    private func makeRecord(
        for command: PaletteCommand,
        count: Int,
        lastExecutedAt: Date
    ) -> CommandUsageRecord {
        CommandUsageRecord(
            commandKey: commandKey(for: command),
            executionCount: count,
            lastExecutedAt: lastExecutedAt
        )
    }

    private func commandKey(for command: PaletteCommand) -> String {
        CommandUsageStore.commandKey(for: command)
    }
}

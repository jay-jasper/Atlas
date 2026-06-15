import XCTest
@testable import Atlas

@MainActor
final class CommandUsageStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "CommandUsageStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testCommandKeyUsesCategoryAndTitle() {
        let command = makeCommand(title: "Capture Area", category: "Atlas")

        XCTAssertEqual(CommandUsageStore.commandKey(for: command), "Atlas|Capture Area")
    }

    func testRecordUsageCreatesRecord() {
        let date = Date(timeIntervalSince1970: 100)
        let store = CommandUsageStore(defaults: defaults, dateProvider: { date })
        let command = makeCommand(title: "Capture Area", category: "Atlas")

        store.recordUsage(for: command)

        XCTAssertEqual(store.usageRecords(), [
            "Atlas|Capture Area": CommandUsageRecord(
                commandKey: "Atlas|Capture Area",
                executionCount: 1,
                lastExecutedAt: date
            ),
        ])
    }

    func testRecordUsageIncrementsCountAndUpdatesRecency() {
        var dates = [
            Date(timeIntervalSince1970: 100),
            Date(timeIntervalSince1970: 200),
        ]
        let store = CommandUsageStore(defaults: defaults) {
            dates.removeFirst()
        }
        let command = makeCommand(title: "Capture Area", category: "Atlas")

        store.recordUsage(for: command)
        store.recordUsage(for: command)

        XCTAssertEqual(store.usageRecords()["Atlas|Capture Area"], CommandUsageRecord(
            commandKey: "Atlas|Capture Area",
            executionCount: 2,
            lastExecutedAt: Date(timeIntervalSince1970: 200)
        ))
    }

    func testRecordsPersistAcrossStoreInstances() {
        let date = Date(timeIntervalSince1970: 100)
        let firstStore = CommandUsageStore(defaults: defaults, dateProvider: { date })
        let command = makeCommand(title: "Open Screenshot Library", category: "Atlas")

        firstStore.recordUsage(for: command)
        let secondStore = CommandUsageStore(defaults: defaults)

        XCTAssertEqual(secondStore.usageRecords()["Atlas|Open Screenshot Library"], CommandUsageRecord(
            commandKey: "Atlas|Open Screenshot Library",
            executionCount: 1,
            lastExecutedAt: date
        ))
    }

    func testClearRemovesRecords() {
        let store = CommandUsageStore(defaults: defaults)
        let command = makeCommand(title: "Capture Area", category: "Atlas")
        store.recordUsage(for: command)

        store.clear()

        XCTAssertEqual(store.usageRecords(), [:])
    }

    private func makeCommand(
        title: String,
        category: String
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
}

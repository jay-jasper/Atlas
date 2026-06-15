import XCTest
@testable import Atlas

@MainActor
final class CustomAutomationStoreTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var fileURL: URL!
    private var store: CustomAutomationStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        fileURL = temporaryDirectory.appendingPathComponent("custom-automation.json")
        store = CustomAutomationStore(fileURL: fileURL)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        store = nil
        fileURL = nil
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    func testEmptyLoadReturnsNoCommands() {
        XCTAssertEqual(store.commands(), [])
    }

    func testSaveAndLoadRoundTrip() throws {
        let command = makeCommand(
            title: "Open Logs",
            command: "tail -f atlas.log",
            kind: .shell,
            keywords: [" logs ", "", "debug"]
        )

        try store.save([command])

        XCTAssertEqual(store.commands(), [command])
        XCTAssertEqual(store.commands().first?.keywords, ["logs", "debug"])
    }

    func testUpsertSortsCommandsByTitle() throws {
        let second = makeCommand(title: "Build", command: "swift build")
        let first = makeCommand(title: "Analyze", command: "swift test")

        try store.upsert(second)
        try store.upsert(first)

        XCTAssertEqual(store.commands().map(\.title), ["Analyze", "Build"])
    }

    func testUpsertReplacesExistingCommandByID() throws {
        let id = UUID()
        let original = makeCommand(id: id, title: "Build", command: "swift build")
        let updated = makeCommand(id: id, title: "Build App", command: "xcodebuild test")

        try store.upsert(original)
        try store.upsert(updated)

        XCTAssertEqual(store.commands(), [updated])
    }

    func testDeleteRemovesCommand() throws {
        let kept = makeCommand(title: "Kept", command: "echo kept")
        let removed = makeCommand(title: "Removed", command: "echo removed")
        try store.save([kept, removed])

        try store.delete(id: removed.id)

        XCTAssertEqual(store.commands(), [kept])
    }

    func testRejectsEmptyTitle() {
        XCTAssertThrowsError(try store.save([makeCommand(title: " ", command: "echo ok")])) { error in
            XCTAssertEqual(error as? CustomAutomationStoreError, .invalidCommand)
        }
    }

    func testRejectsEmptyCommand() {
        XCTAssertThrowsError(try store.save([makeCommand(title: "Empty", command: " ")])) { error in
            XCTAssertEqual(error as? CustomAutomationStoreError, .invalidCommand)
        }
    }

    func testRejectsInvalidTimeout() {
        XCTAssertThrowsError(try store.save([makeCommand(title: "Timeout", command: "echo ok", timeoutSeconds: 0)])) { error in
            XCTAssertEqual(error as? CustomAutomationStoreError, .invalidCommand)
        }
    }

    func testRejectsDuplicateTitlesCaseInsensitively() {
        let first = makeCommand(title: "Build", command: "swift build")
        let second = makeCommand(title: "build", command: "cargo build")

        XCTAssertThrowsError(try store.save([first, second])) { error in
            XCTAssertEqual(error as? CustomAutomationStoreError, .duplicateTitle)
        }
    }

    private func makeCommand(
        id: UUID = UUID(),
        title: String,
        command: String,
        kind: CustomAutomationKind = .shell,
        keywords: [String] = [],
        timeoutSeconds: TimeInterval = 10
    ) -> CustomAutomationCommand {
        CustomAutomationCommand(
            id: id,
            title: title,
            command: command,
            kind: kind,
            keywords: keywords,
            timeoutSeconds: timeoutSeconds,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
    }
}

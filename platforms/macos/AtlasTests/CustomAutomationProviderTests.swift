import XCTest
@testable import Atlas

@MainActor
final class CustomAutomationProviderTests: XCTestCase {
    func testDisabledFeatureGateReturnsNoResults() {
        let provider = CustomAutomationProvider(store: StubAutomationStore(commands: [deployCommand()]), isEnabled: { false })

        XCTAssertTrue(provider.results(for: "deploy").isEmpty)
    }

    func testBlankQueryReturnsNoResults() {
        let provider = CustomAutomationProvider(store: StubAutomationStore(commands: [deployCommand()]), isEnabled: { true })

        XCTAssertTrue(provider.results(for: " \n ").isEmpty)
    }

    func testQueryMatchesTitleCommandKindAndKeywords() {
        let command = deployCommand()
        let provider = CustomAutomationProvider(store: StubAutomationStore(commands: [command]), isEnabled: { true })

        XCTAssertEqual(provider.results(for: "deploy").map(\.id), [command.id])
        XCTAssertEqual(provider.results(for: "npm").map(\.id), [command.id])
        XCTAssertEqual(provider.results(for: "shell").map(\.id), [command.id])
        XCTAssertEqual(provider.results(for: "preview").map(\.id), [command.id])
    }

    func testResultsAreCappedToFive() {
        let commands = (0..<8).map { index in
            CustomAutomationCommand(title: "Deploy \(index)", command: "echo \(index)", kind: .shell)
        }
        let provider = CustomAutomationProvider(store: StubAutomationStore(commands: commands), isEnabled: { true })

        XCTAssertEqual(provider.results(for: "deploy").count, 5)
    }

    func testResultMetadataAndAction() {
        let command = deployCommand()
        let provider = CustomAutomationProvider(store: StubAutomationStore(commands: [command]), isEnabled: { true })

        let result = provider.results(for: "deploy").first

        XCTAssertEqual(result?.category, "Automation")
        XCTAssertEqual(result?.title, "Run Deploy Preview")
        XCTAssertEqual(result?.subtitle, "Shell automation")
        XCTAssertEqual(result?.icon, .sfSymbol("terminal"))
        XCTAssertEqual(result?.keywords, ["preview", "release", "shell", "automation", "run"])
        if case .push(.automationOutput(command))? = result?.action {
        } else {
            XCTFail("expected automation output push action")
        }
    }

    func testPythonResultUsesCurlyBracesIcon() {
        let command = CustomAutomationCommand(title: "Inspect", command: "print('ok')", kind: .python)
        let provider = CustomAutomationProvider(store: StubAutomationStore(commands: [command]), isEnabled: { true })

        XCTAssertEqual(provider.results(for: "python").first?.icon, .sfSymbol("curlybraces"))
    }

    func testGeneratedTitleProducesStableUsageStoreKey() throws {
        let command = deployCommand()
        let provider = CustomAutomationProvider(store: StubAutomationStore(commands: [command]), isEnabled: { true })
        let result = try XCTUnwrap(provider.results(for: "deploy").first)

        XCTAssertEqual(CommandUsageStore.commandKey(for: result), "Automation|Run Deploy Preview")
    }

    func testStoreRejectsDuplicateTitlesSoUsageKeysDoNotMergeDifferentCommands() {
        let first = deployCommand()
        let second = CustomAutomationCommand(title: "deploy preview", command: "echo other", kind: .shell)
        let store = StubAutomationStore(commands: [])

        XCTAssertThrowsError(try store.save([first, second])) { error in
            XCTAssertEqual(error as? CustomAutomationStoreError, .duplicateTitle)
        }
    }

    private func deployCommand() -> CustomAutomationCommand {
        CustomAutomationCommand(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Deploy Preview",
            command: "npm run deploy",
            kind: .shell,
            keywords: ["preview", "release"],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
    }
}

private final class StubAutomationStore: CustomAutomationStoring {
    private var storedCommands: [CustomAutomationCommand]

    init(commands: [CustomAutomationCommand]) {
        storedCommands = commands
    }

    func commands() -> [CustomAutomationCommand] {
        storedCommands
    }

    func save(_ commands: [CustomAutomationCommand]) throws {
        guard commands.allSatisfy(\.isValid) else {
            throw CustomAutomationStoreError.invalidCommand
        }
        let normalizedTitles = commands.map { $0.title.lowercased() }
        guard Set(normalizedTitles).count == normalizedTitles.count else {
            throw CustomAutomationStoreError.duplicateTitle
        }
        storedCommands = commands
    }

    func upsert(_ command: CustomAutomationCommand) throws {
        try save(storedCommands + [command])
    }

    func delete(id: UUID) throws {
        storedCommands.removeAll { $0.id == id }
    }
}

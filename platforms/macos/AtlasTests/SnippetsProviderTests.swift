import XCTest
@testable import Atlas

@MainActor
final class SnippetsProviderTests: XCTestCase {
    func testEmptyQueryReturnsNoResults() {
        let provider = SnippetsProvider(snippetProvider: FixtureSnippetProvider())

        XCTAssertTrue(provider.results(for: " \n ").isEmpty)
    }

    func testSnippetQueryReturnsEmailGreetingAndBugReport() {
        let provider = SnippetsProvider(snippetProvider: FixtureSnippetProvider())

        let results = provider.results(for: "snippet")

        XCTAssertEqual(results.map(\.title), [
            "Copy Email Greeting",
            "Copy Bug Report",
        ])
    }

    func testTitleQueryMeetingReturnsMeetingNotes() {
        let provider = SnippetsProvider(snippetProvider: FixtureSnippetProvider())

        let results = provider.results(for: "meeting")

        XCTAssertEqual(results.map(\.title), ["Copy Meeting Notes"])
    }

    func testBodyQueryReproduceReturnsBugReport() {
        let provider = SnippetsProvider(snippetProvider: FixtureSnippetProvider())

        let results = provider.results(for: "reproduce")

        XCTAssertEqual(results.map(\.title), ["Copy Bug Report"])
    }

    func testKeywordQueryHelloReturnsEmailGreeting() {
        let provider = SnippetsProvider(snippetProvider: FixtureSnippetProvider())

        let results = provider.results(for: "hello")

        XCTAssertEqual(results.map(\.title), ["Copy Email Greeting"])
    }

    func testAllSnippetResultsHaveSnippetCategoryAndTextQuoteIcon() {
        let provider = SnippetsProvider(snippetProvider: FixtureSnippetProvider())

        let results = provider.results(for: "snippet")

        XCTAssertTrue(results.allSatisfy { $0.category == "Snippet" })
        XCTAssertTrue(results.allSatisfy { $0.icon == .sfSymbol("text.quote") })
    }

    func testExecutingMeetingResultCopiesBody() {
        let clipboard = FakeSnippetClipboard()
        let logger = FakeSnippetPrivacyPulseAccessLogger()
        let provider = SnippetsProvider(
            snippetProvider: FixtureSnippetProvider(),
            clipboard: clipboard,
            accessLogger: logger
        )

        let result = provider.results(for: "meeting").first
        if case .execute(let execute)? = result?.action {
            execute()
        } else {
            XCTFail("expected executable snippet result")
        }

        XCTAssertEqual(clipboard.writtenText, "Notes:\n- item")
        XCTAssertEqual(logger.events.map(\.title), ["Clipboard Write"])
        XCTAssertEqual(logger.events.first?.category, .clipboard)
    }

    func testResultsAreCappedToFive() {
        let snippets = (1...8).map { index in
            Snippet(
                id: "fixture-\(index)",
                title: "Fixture \(index)",
                body: "Fixture body \(index)",
                keywords: ["fixture"]
            )
        }
        let provider = SnippetsProvider(snippetProvider: FixtureSnippetProvider(snippets: snippets))

        let results = provider.results(for: "fixture")

        XCTAssertEqual(results.count, 5)
        XCTAssertEqual(results.map(\.title), [
            "Copy Fixture 1",
            "Copy Fixture 2",
            "Copy Fixture 3",
            "Copy Fixture 4",
            "Copy Fixture 5",
        ])
    }
}

private final class FakeSnippetPrivacyPulseAccessLogger: PrivacyPulseAccessLogging {
    struct Event: Equatable {
        let category: PrivacyPulseCategory
        let title: String
        let detail: String
    }

    private(set) var events: [Event] = []

    func record(category: PrivacyPulseCategory, title: String, detail: String) {
        events.append(Event(category: category, title: title, detail: detail))
    }
}

private struct FixtureSnippetProvider: SnippetProviding {
    private let fixtureSnippets: [Snippet]

    init(snippets: [Snippet] = Self.defaultSnippets) {
        self.fixtureSnippets = snippets
    }

    func snippets() -> [Snippet] {
        fixtureSnippets
    }

    private static let defaultSnippets: [Snippet] = [
        Snippet(
            id: "email-greeting",
            title: "Email Greeting",
            body: "Hi,\n\nThanks for reading this snippet.",
            keywords: ["email", "greeting", "hello"]
        ),
        Snippet(
            id: "meeting-notes",
            title: "Meeting Notes",
            body: "Notes:\n- item",
            keywords: ["notes", "agenda"]
        ),
        Snippet(
            id: "bug-report",
            title: "Bug Report",
            body: "Steps to reproduce:\n1. Open the app",
            keywords: ["bug", "report", "snippet"]
        ),
    ]
}

private final class FakeSnippetClipboard: ClipboardReading {
    private(set) var changeCount = 0
    private(set) var writtenText: String?

    func string() -> String? {
        writtenText
    }

    func imageMetadata() -> ClipboardImageMetadata? {
        nil
    }

    func setString(_ text: String) {
        writtenText = text
        changeCount += 1
    }
}

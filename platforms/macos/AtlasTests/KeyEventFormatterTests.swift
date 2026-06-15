import XCTest
@testable import Atlas

@MainActor
final class KeyEventFormatterTests: XCTestCase {
    func testModifierOrder() {
        XCTAssertEqual(KeyEventFormatter.modifierString([.command, .shift, .control, .option]), "⌃⌥⇧⌘")
        XCTAssertEqual(KeyEventFormatter.modifierString([.command]), "⌘")
        XCTAssertEqual(KeyEventFormatter.modifierString([]), "")
    }

    func testShortcutDisplayUppercases() {
        XCTAssertEqual(KeyEventFormatter.display(modifiers: [.command, .shift], characters: "a", keyCode: 0), "⇧⌘A")
    }

    func testPlainTypingKeepsCase() {
        XCTAssertEqual(KeyEventFormatter.display(modifiers: [], characters: "a", keyCode: 0), "a")
    }

    func testSpecialKeys() {
        XCTAssertEqual(KeyEventFormatter.display(modifiers: [], characters: "", keyCode: 49), "Space")
        XCTAssertEqual(KeyEventFormatter.display(modifiers: [.command], characters: "", keyCode: 36), "⌘↩")
        XCTAssertEqual(KeyEventFormatter.display(modifiers: [], characters: "", keyCode: 123), "←")
    }

    func testUnknownKeyFallback() {
        XCTAssertEqual(KeyEventFormatter.display(modifiers: [], characters: "", keyCode: 9999), "?")
    }
}

@MainActor
final class KeyboardDisplayServiceTests: XCTestCase {
    func testRecordAppendsFormatted() {
        let service = KeyboardDisplayService()
        service.record(modifiers: [.command], characters: "c", keyCode: 8)
        XCTAssertEqual(service.recent.map(\.text), ["⌘C"])
    }

    func testRecentIsCapped() {
        let service = KeyboardDisplayService()
        for _ in 0..<20 { service.record(modifiers: [], characters: "x", keyCode: 0) }
        XCTAssertLessThanOrEqual(service.recent.count, 12)
    }

    func testClear() {
        let service = KeyboardDisplayService()
        service.record(modifiers: [], characters: "a", keyCode: 0)
        service.clear()
        XCTAssertTrue(service.recent.isEmpty)
    }
}

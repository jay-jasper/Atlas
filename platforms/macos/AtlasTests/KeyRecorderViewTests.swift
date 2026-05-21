import XCTest
import AppKit
@testable import Atlas

@MainActor
final class KeyRecorderViewTests: XCTestCase {
    func testDefaultHotkeyLoadedFromDefaults() {
        let defaults = UserDefaults(suiteName: "test.keyrecorder")!
        defaults.removeObject(forKey: "palette.hotkey.keyCode")
        defaults.removeObject(forKey: "palette.hotkey.modifiers")

        let config = HotkeyConfig.load(from: defaults)
        XCTAssertEqual(config.keyCode, 49)  // Space
        XCTAssertEqual(config.modifiers, NSEvent.ModifierFlags.option.rawValue)
    }

    func testSavedHotkeyRoundTrips() {
        let defaults = UserDefaults(suiteName: "test.keyrecorder")!
        let config = HotkeyConfig(keyCode: 36, modifiers: NSEvent.ModifierFlags.command.rawValue)
        config.save(to: defaults)

        let loaded = HotkeyConfig.load(from: defaults)
        XCTAssertEqual(loaded.keyCode, 36)
        XCTAssertEqual(loaded.modifiers, NSEvent.ModifierFlags.command.rawValue)

        defaults.removeObject(forKey: "palette.hotkey.keyCode")
        defaults.removeObject(forKey: "palette.hotkey.modifiers")
    }

    func testValidationRequiresAtLeastOneModifier() {
        XCTAssertTrue(HotkeyConfig.isValid(modifiers: .option))
        XCTAssertTrue(HotkeyConfig.isValid(modifiers: .command))
        XCTAssertTrue(HotkeyConfig.isValid(modifiers: .control))
        XCTAssertTrue(HotkeyConfig.isValid(modifiers: .shift))
        XCTAssertFalse(HotkeyConfig.isValid(modifiers: []))
    }

    func testDisplayStringFormatting() {
        let config = HotkeyConfig(
            keyCode: 49,
            modifiers: NSEvent.ModifierFlags.option.rawValue
        )
        let display = config.displayString(keyChar: "Space")
        XCTAssertEqual(display, "⌥Space")
    }

    func testConflictDetectionFindsAreaCaptureHotkey() {
        let config = HotkeyConfig(
            keyCode: 21,
            modifiers: NSEvent.ModifierFlags([.control, .shift]).rawValue
        )
        XCTAssertTrue(config.conflictsWithAreaCapture)
    }

    func testNoConflictForDefaultPaletteHotkey() {
        let config = HotkeyConfig(
            keyCode: 49,
            modifiers: NSEvent.ModifierFlags.option.rawValue
        )
        XCTAssertFalse(config.conflictsWithAreaCapture)
    }
}

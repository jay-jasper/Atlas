import Foundation

/// Modifier flags for a keystroke (subset of CGEventFlags we display).
struct KeyModifiers: OptionSet, Equatable {
    let rawValue: Int
    static let control = KeyModifiers(rawValue: 1 << 0)
    static let option = KeyModifiers(rawValue: 1 << 1)
    static let shift = KeyModifiers(rawValue: 1 << 2)
    static let command = KeyModifiers(rawValue: 1 << 3)
}

/// Formats a keystroke into a KeyCastr-style display string. Pure & testable.
enum KeyEventFormatter {
    /// Symbols in canonical macOS order: ⌃⌥⇧⌘.
    static func modifierString(_ modifiers: KeyModifiers) -> String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result
    }

    /// Human-readable names for special keys, keyed by macOS virtual keycode.
    static let specialKeys: [Int: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        117: "⌦", 116: "⇞", 121: "⇟", 115: "↖", 119: "↘",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
    ]

    /// Builds the display token for a key event. `characters` is the typed text
    /// (may be empty for special keys); `keyCode` resolves named keys.
    static func display(modifiers: KeyModifiers, characters: String, keyCode: Int) -> String {
        let mods = modifierString(modifiers)
        let key: String
        if let special = specialKeys[keyCode] {
            key = special
        } else if !characters.isEmpty {
            // Uppercase letters look cleaner for shortcut display.
            key = modifiers.contains(.command) || modifiers.contains(.control)
                ? characters.uppercased()
                : characters
        } else {
            key = "?"
        }
        return mods + key
    }
}

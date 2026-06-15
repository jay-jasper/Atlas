import Foundation

/// A mechanical keyboard sound pack. Variant selection is deterministic per
/// keycode so the same key sounds consistent — pure & unit-testable.
enum KeyboardSoundPack: String, CaseIterable, Identifiable {
    case typewriter
    case mechanical
    case soft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .typewriter: return "Typewriter"
        case .mechanical: return "Mechanical"
        case .soft: return "Soft"
        }
    }

    /// macOS system sounds standing in for each pack's keypress samples.
    var variants: [String] {
        switch self {
        case .typewriter: return ["Tink", "Pop", "Morse"]
        case .mechanical: return ["Pop", "Bottle", "Tink"]
        case .soft: return ["Pop", "Pop"]
        }
    }

    /// Distinct sound for the "modifier/return" class of keys.
    var accentSound: String { "Bottle" }
}

enum KeyboardSoundSelector {
    /// Picks a variant index for a keycode (stable per key).
    static func variantIndex(keyCode: Int, variantCount: Int) -> Int {
        guard variantCount > 0 else { return 0 }
        return abs(keyCode) % variantCount
    }

    /// The sound name to play for a keystroke in a pack. Return/space/modifiers
    /// (keycodes 36/48/49) use the accent sound.
    static func sound(for keyCode: Int, pack: KeyboardSoundPack) -> String {
        if keyCode == 36 || keyCode == 48 || keyCode == 49 {
            return pack.accentSound
        }
        let index = variantIndex(keyCode: keyCode, variantCount: pack.variants.count)
        return pack.variants[index]
    }
}

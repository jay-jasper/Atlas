import Foundation

/// App events that can trigger an audio cue.
enum SoundEvent: String, CaseIterable, Identifiable {
    case appSwitch
    case volumeChange
    case screenshotCaptured
    case featureToggled
    case clipboardCopied

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appSwitch: return "App Switch"
        case .volumeChange: return "Volume Change"
        case .screenshotCaptured: return "Screenshot"
        case .featureToggled: return "Feature Toggle"
        case .clipboardCopied: return "Clipboard Copy"
        }
    }
}

/// Maps events to built-in macOS system sound names (in /System/Library/Sounds).
/// Pure — fully unit-testable.
enum SoundFeedbackMapping {
    static let defaults: [SoundEvent: String] = [
        .appSwitch: "Tink",
        .volumeChange: "Pop",
        .screenshotCaptured: "Grab",
        .featureToggled: "Morse",
        .clipboardCopied: "Bottle",
    ]

    static func soundName(for event: SoundEvent, overrides: [SoundEvent: String] = [:]) -> String? {
        overrides[event] ?? defaults[event]
    }
}

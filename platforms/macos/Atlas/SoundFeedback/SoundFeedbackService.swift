import AppKit
import Foundation

/// Plays a named system sound. Injected so the service is testable.
protocol SoundPlaying {
    func play(named name: String)
}

struct NSSoundPlayer: SoundPlaying {
    func play(named name: String) {
        NSSound(named: name)?.play()
    }
}

@MainActor
final class SoundFeedbackService: ObservableObject {
    @Published var isEnabled = false
    @Published private(set) var enabledEvents: Set<SoundEvent> = Set(SoundEvent.allCases)

    private let player: SoundPlaying

    init(player: SoundPlaying = NSSoundPlayer()) {
        self.player = player
    }

    func toggle(_ event: SoundEvent) {
        if enabledEvents.contains(event) { enabledEvents.remove(event) } else { enabledEvents.insert(event) }
    }

    func isEnabled(_ event: SoundEvent) -> Bool { enabledEvents.contains(event) }

    /// Plays the cue for an event if feedback and that event are enabled.
    func fire(_ event: SoundEvent) {
        guard isEnabled, enabledEvents.contains(event),
              let name = SoundFeedbackMapping.soundName(for: event) else { return }
        player.play(named: name)
    }
}

import SwiftUI

struct SoundFeedbackPanel: View {
    @ObservedObject var service: SoundFeedbackService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Sound Feedback", systemImage: "speaker.wave.2.bubble")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $service.isEnabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }

            ForEach(SoundEvent.allCases) { event in
                HStack {
                    Toggle(isOn: Binding(
                        get: { service.isEnabled(event) },
                        set: { _ in service.toggle(event) }
                    )) {
                        Text(event.title).font(.caption)
                    }
                    .toggleStyle(.checkbox)
                    .disabled(!service.isEnabled)
                    Spacer()
                    Button { service.fire(event) } label: { Image(systemName: "play.circle") }
                        .buttonStyle(.plain)
                        .disabled(!service.isEnabled)
                }
            }

            Text("Plays built-in macOS sounds for app events.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

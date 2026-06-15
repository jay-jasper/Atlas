import SwiftUI

struct KeyboardSoundPanel: View {
    @ObservedObject var service: KeyboardSoundService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Keyboard Sounds", systemImage: "pianokeys")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $service.isEnabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }

            Picker("Pack", selection: $service.pack) {
                ForEach(KeyboardSoundPack.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Volume").font(.caption)
                Slider(value: $service.volume, in: 0...1)
                Button("Test") { service.playKey(keyCode: 0) }.controlSize(.small)
            }

            Text("Plays mechanical keyboard sounds as you type.")
                .font(.caption).foregroundStyle(.secondary)

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

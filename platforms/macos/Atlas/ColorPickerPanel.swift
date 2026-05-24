import SwiftUI

struct ColorPickerPanel: View {
    @ObservedObject var service: ColorPickerService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Color Picker", systemImage: "eyedropper.halffull")
                    .font(.headline)
                Spacer()
                Button("Pick Color") {
                    service.pickColor()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if let last = service.lastPicked {
                ColorSwatchRow(color: last, label: "Last picked")
            }

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !service.history.isEmpty {
                Divider()
                Text("Recent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                    ForEach(service.history) { color in
                        ColorSwatchButton(color: color) {
                            service.copyToClipboard(color.hex)
                        }
                        .contextMenu {
                            Button("Copy Hex") { service.copyToClipboard(color.hex) }
                            Button("Copy RGB") { service.copyToClipboard(color.rgbString) }
                            Button("Copy HSL") { service.copyToClipboard(color.hslString) }
                            Divider()
                            Button("Remove", role: .destructive) { service.removeFromHistory(id: color.id) }
                        }
                    }
                }

                Button("Clear History", role: .destructive) {
                    service.clearHistory()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

private struct ColorSwatchRow: View {
    let color: PickedColor
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color.color)
                .frame(width: 32, height: 32)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text(color.hex).font(.system(.body, design: .monospaced)).bold()
                Text(color.rgbString).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ColorSwatchButton: View {
    let color: PickedColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color.color)
                .frame(height: 28)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
                .overlay(
                    Text(color.hex)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(radius: 1)
                )
        }
        .buttonStyle(.plain)
        .help(color.hex)
    }
}

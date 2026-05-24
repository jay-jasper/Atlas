import SwiftUI

struct FnKeyPanel: View {
    @ObservedObject var service: FnKeyService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Fn Key Switcher", systemImage: "keyboard")
                    .font(.headline)
                Spacer()
                Button {
                    service.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh current mode")
            }

            if !service.isAvailable {
                Text(service.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(FnKeyMode.allCases) { mode in
                    FnKeyModeRow(
                        mode: mode,
                        isSelected: service.currentMode == mode
                    ) {
                        service.setMode(mode)
                    }
                }

                if !service.statusMessage.isEmpty {
                    Text(service.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding()
    }
}

private struct FnKeyModeRow: View {
    let mode: FnKeyMode
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: mode.systemImage)
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? .white : .primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isSelected ? .white : .primary)
                    Text(mode.description)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            .padding(10)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

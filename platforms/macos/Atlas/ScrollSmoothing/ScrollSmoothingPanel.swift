import SwiftUI

struct ScrollSmoothingPanel: View {
    @ObservedObject var service: ScrollSmoothingService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Scroll Smoothing", systemImage: "computermouse")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $service.isEnabled)
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }

            HStack {
                Text("Smoothness").font(.caption).frame(width: 80, alignment: .leading)
                Slider(value: $service.smoothing, in: 0...0.97)
                Text(String(format: "%.0f%%", service.smoothing * 100))
                    .font(.caption.monospacedDigit()).frame(width: 36)
            }

            HStack {
                Text("Speed").font(.caption).frame(width: 80, alignment: .leading)
                Slider(value: $service.step, in: 0.5...3.0)
                Text(String(format: "%.1f×", service.step))
                    .font(.caption.monospacedDigit()).frame(width: 36)
            }

            Text("Smooths line-based scrolling for non-Apple mice.")
                .font(.caption).foregroundStyle(.secondary)

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

import SwiftUI

struct AspectGuidePanel: View {
    @ObservedObject var service: AspectGuideService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Aspect Ratio Guide", systemImage: "rectangle.dashed")
                    .font(.headline)
                Spacer()
                Toggle("Overlay", isOn: Binding(
                    get: { service.isOverlayVisible },
                    set: { _ in service.toggleOverlay() }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            Picker("Ratio", selection: $service.selectedPreset) {
                ForEach(AspectRatioPreset.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            // Live preview of the fitted guide inside a sample frame.
            GeometryReader { geo in
                let container = CGSize(width: geo.size.width, height: 120)
                let rect = service.rect(in: container)
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color.secondary.opacity(0.08))
                    Rectangle()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
            .frame(height: 120)

            Text("Frames your content to \(service.selectedPreset.rawValue) while recording.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

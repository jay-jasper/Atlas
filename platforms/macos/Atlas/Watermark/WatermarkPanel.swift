import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WatermarkPanel: View {
    @ObservedObject var service: WatermarkService
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Watermark Toolkit", systemImage: "drop.triangle")
                .font(.headline)

            TextField("Watermark text", text: $service.text)
                .textFieldStyle(.roundedBorder)

            Picker("Position", selection: $service.position) {
                ForEach(WatermarkPosition.allCases) { Text($0.rawValue).tag($0) }
            }

            HStack {
                Text("Opacity").font(.caption)
                Slider(value: $service.opacity, in: 0.1...1.0)
                Text(String(format: "%.0f%%", service.opacity * 100))
                    .font(.caption.monospacedDigit()).frame(width: 36)
            }

            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
                .frame(height: 50)
                .overlay(Text("Drop images to watermark").font(.caption).foregroundStyle(.secondary))
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    handleDrop(providers)
                    return true
                }

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            service.applyToFiles(urls)
        }
    }
}

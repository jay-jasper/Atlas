import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GIFProcessingPanel: View {
    @ObservedObject var service: GIFProcessingService
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("GIF Post-Processing", systemImage: "photo.stack")
                .font(.headline)

            HStack {
                Text("Scale").font(.caption).frame(width: 64, alignment: .leading)
                Slider(value: $service.scale, in: 0.25...1.0)
                Text(String(format: "%.0f%%", service.scale * 100))
                    .font(.caption.monospacedDigit()).frame(width: 40)
            }

            HStack {
                Text("Max edge").font(.caption).frame(width: 64, alignment: .leading)
                Slider(value: $service.maxDimension, in: 0...1200)
                Text(service.maxDimension == 0 ? "Off" : "\(Int(service.maxDimension))px")
                    .font(.caption.monospacedDigit()).frame(width: 40)
            }

            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
                .frame(height: 50)
                .overlay(Text("Drop a GIF to re-encode").font(.caption).foregroundStyle(.secondary))
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    for provider in providers {
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in
                            if let url { Task { @MainActor in service.process(url: url) } }
                        }
                    }
                    return true
                }

            if let size = service.lastOutputSize {
                Text("Output: \(Int(size.width))×\(Int(size.height))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !service.statusMessage.isEmpty {
                Text(service.statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

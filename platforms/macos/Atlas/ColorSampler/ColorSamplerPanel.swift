import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ColorSamplerPanel: View {
    @ObservedObject var service: ColorSamplerService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Color Sampler", systemImage: "eyedropper.halffull")
                    .font(.headline)
                Spacer()
                Button("Open Frame…") { chooseImage() }.controlSize(.small)
            }

            if let image = service.image {
                GeometryReader { geo in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let norm = CGPoint(x: location.x / geo.size.width, y: location.y / geo.size.height)
                            service.sample(atNormalized: norm)
                        }
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                if let hex = service.sampledHex, let color = service.sampledColor {
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(color))
                            .frame(width: 20, height: 20)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                        Text(hex).font(.caption.monospaced())
                        Spacer()
                        Button("Copy") { service.copyHex() }.controlSize(.small)
                    }
                } else {
                    Text("Tap the frame to sample a color.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Open a video frame or image to sample colors from it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            service.loadImage(at: url)
        }
    }
}

import SwiftUI

struct WebWallpaperPanel: View {
    @ObservedObject var service: WebWallpaperService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Web Wallpaper", systemImage: "menubar.dock.rectangle")
                    .font(.headline)
                Spacer()
                if service.isActive {
                    Button("Remove") { service.hide() }.controlSize(.small)
                }
            }

            HStack {
                TextField("example.com or full URL", text: $service.urlString)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { service.setWallpaper() }
                Button("Set") { service.setWallpaper() }
                    .buttonStyle(.borderedProminent)
            }

            HStack {
                ForEach(WebWallpaperURL.presets, id: \.name) { preset in
                    Button(preset.name) {
                        service.urlString = preset.url
                        service.setWallpaper()
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }
            }

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

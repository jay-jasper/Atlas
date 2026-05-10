import SwiftUI

struct ScreenshotPanel: View {
    let onSelectArea: () -> Void
    let onFullScreen: () -> Void

    var body: some View {
        Group {
            Text("Screenshot").font(.subheadline).foregroundColor(.secondary)
            HStack {
                Button(action: onSelectArea) {
                    Label("Area", systemImage: "selection.pin.in.out")
                }
                .buttonStyle(.borderedProminent)

                Button(action: onFullScreen) {
                    Label("Full", systemImage: "macwindow")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

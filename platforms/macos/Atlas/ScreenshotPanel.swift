import SwiftUI

struct ScreenshotPanel: View {
    let onCaptureDesktop: () -> Void
    let onCaptureWindow: () -> Void
    let onCaptureArea: () -> Void

    var body: some View {
        Group {
            Text("Screenshot").font(.subheadline).foregroundColor(.secondary)
            HStack {
                captureButton(for: .desktop, action: onCaptureDesktop, prominent: true)
                captureButton(for: .window, action: onCaptureWindow, prominent: false)
                captureButton(for: .area, action: onCaptureArea, prominent: false)
            }
        }
    }

    @ViewBuilder
    private func captureButton(
        for mode: ScreenshotCaptureMode,
        action: @escaping () -> Void,
        prominent: Bool
    ) -> some View {
        if prominent {
            Button(action: action) {
                Label(mode.title, systemImage: mode.systemImage)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(action: action) {
                Label(mode.title, systemImage: mode.systemImage)
            }
            .buttonStyle(.bordered)
        }
    }
}

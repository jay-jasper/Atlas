import SwiftUI

struct ScreenshotPanel: View {
    let capabilities: ScreenshotCaptureCapabilities
    let onCaptureDesktop: () -> Void
    let onCaptureWindow: () -> Void
    let onCaptureArea: () -> Void

    var body: some View {
        Group {
            Text("Screenshot").font(.subheadline).foregroundColor(.secondary)
            HStack {
                if capabilities.desktop {
                    captureButton(for: .desktop, action: onCaptureDesktop, prominent: true)
                }
                if capabilities.window {
                    captureButton(for: .window, action: onCaptureWindow, prominent: !capabilities.desktop)
                }
                if capabilities.area {
                    captureButton(
                        for: .area,
                        action: onCaptureArea,
                        prominent: !capabilities.desktop && !capabilities.window
                    )
                }
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

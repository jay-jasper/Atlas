import AppKit
import SwiftUI

/// A compact rainbow swatch that opens the macOS system color wheel positioned
/// right where it was clicked (next to the toolbar) — instead of SwiftUI's
/// `ColorPicker`, whose well renders oddly in a dense toolbar and whose panel
/// pops up far away in a corner.
struct ColorWheelButton: View {
    @Binding var color: Color
    var onChange: () -> Void = {}

    var body: some View {
        Button {
            ScreenshotColorPanelController.shared.present(initial: NSColor(color)) { newColor in
                color = newColor
                onChange()
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            gradient: Gradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red]),
                            center: .center
                        ),
                        lineWidth: 3
                    )
                Circle().fill(color).frame(width: 8, height: 8)
            }
            .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .help("更多颜色")
    }
}

/// Drives `NSColorPanel.shared`: opens it next to the cursor, keeps it above the
/// (screen-saver-level) capture overlay, and forwards live color changes.
final class ScreenshotColorPanelController: NSObject {
    static let shared = ScreenshotColorPanelController()

    private var handler: ((Color) -> Void)?

    func present(initial: NSColor, _ onChange: @escaping (Color) -> Void) {
        handler = onChange
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = initial
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        // Float above the capture overlay (which sits at `.screenSaver`).
        panel.level = .screenSaver
        panel.hidesOnDeactivate = false
        // Drop the panel down-right from the click point, so it lands next to the
        // toolbar rather than in a screen corner.
        panel.setFrameTopLeftPoint(NSEvent.mouseLocation)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        handler?(Color(nsColor: sender.color))
    }
}

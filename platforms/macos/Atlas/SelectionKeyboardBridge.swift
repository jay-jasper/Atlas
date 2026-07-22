import AppKit
import SwiftUI

enum SelectionKeyboardCommand {
    case cancel
    case capture
    case nudge(SelectionNudgeDirection, isLargeStep: Bool)
    /// Cycle the aspect-ratio lock for new selections (free → 1:1 → 4:3 → 16:9).
    case cycleAspectLock
}

struct SelectionKeyboardBridge: NSViewRepresentable {
    let onCommand: (SelectionKeyboardCommand) -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onCommand = onCommand
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onCommand = onCommand
        nsView.window?.makeFirstResponder(nsView)
    }
}

final class KeyCaptureView: NSView {
    var onCommand: ((SelectionKeyboardCommand) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        let isLargeStep = event.modifierFlags.contains(.shift)

        switch event.keyCode {
        case 53:
            onCommand?(.cancel)
        case 36, 76:
            onCommand?(.capture)
        case 123:
            onCommand?(.nudge(.left, isLargeStep: isLargeStep))
        case 124:
            onCommand?(.nudge(.right, isLargeStep: isLargeStep))
        case 125:
            onCommand?(.nudge(.down, isLargeStep: isLargeStep))
        case 126:
            onCommand?(.nudge(.up, isLargeStep: isLargeStep))
        case 15: // R — ratio lock
            onCommand?(.cycleAspectLock)
        default:
            super.keyDown(with: event)
        }
    }
}

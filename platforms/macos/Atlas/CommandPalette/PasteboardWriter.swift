import AppKit

/// Writes a string to the general pasteboard. Injectable so palette utility
/// providers can be unit-tested without touching the real pasteboard.
typealias PasteboardWriting = (String) -> Void

enum Pasteboard {
    static let system: PasteboardWriting = { value in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

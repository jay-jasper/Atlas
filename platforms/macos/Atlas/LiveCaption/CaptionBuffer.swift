import Foundation

/// A rolling caption buffer: committed text plus an in-progress partial. Keeps
/// the visible text within a character budget so the overlay stays compact.
/// Pure value logic — fully unit-testable.
struct CaptionBuffer: Equatable {
    private(set) var committed: String = ""
    private(set) var partial: String = ""
    let maxCharacters: Int

    init(maxCharacters: Int = 220) {
        self.maxCharacters = maxCharacters
    }

    /// The text shown on screen: committed + current partial.
    var displayText: String {
        let combined = partial.isEmpty ? committed : "\(committed) \(partial)"
        return combined.trimmingCharacters(in: .whitespaces)
    }

    /// Updates the live (not-yet-final) transcription.
    mutating func updatePartial(_ text: String) {
        partial = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Finalizes the current segment into committed text and trims to budget.
    mutating func commit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        partial = ""
        guard !trimmed.isEmpty else { return }
        committed = committed.isEmpty ? trimmed : "\(committed) \(trimmed)"
        trimToBudget()
    }

    mutating func clear() {
        committed = ""
        partial = ""
    }

    private mutating func trimToBudget() {
        guard committed.count > maxCharacters else { return }
        // Drop whole leading words until within budget.
        var words = committed.split(separator: " ").map(String.init)
        while words.joined(separator: " ").count > maxCharacters, words.count > 1 {
            words.removeFirst()
        }
        committed = words.joined(separator: " ")
    }
}

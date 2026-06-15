import Foundation

/// Searches emoji by name/keyword: `emoji <query>`. Copies the glyph on select.
final class EmojiProvider: CommandProviding {
    private let copy: PasteboardWriting
    private static let maxResults = 6

    init(copy: @escaping PasteboardWriting = Pasteboard.system) {
        self.copy = copy
    }

    struct Emoji { let glyph: String; let name: String; let keywords: [String] }

    static let catalog: [Emoji] = [
        Emoji(glyph: "😀", name: "grinning face", keywords: ["smile", "happy", "grin"]),
        Emoji(glyph: "😂", name: "tears of joy", keywords: ["laugh", "lol", "funny"]),
        Emoji(glyph: "🙂", name: "slightly smiling", keywords: ["smile", "ok"]),
        Emoji(glyph: "😍", name: "heart eyes", keywords: ["love", "crush", "adore"]),
        Emoji(glyph: "😎", name: "sunglasses", keywords: ["cool", "swag"]),
        Emoji(glyph: "🤔", name: "thinking face", keywords: ["think", "hmm", "consider"]),
        Emoji(glyph: "😢", name: "crying face", keywords: ["sad", "cry", "tear"]),
        Emoji(glyph: "😭", name: "loudly crying", keywords: ["sob", "sad", "cry"]),
        Emoji(glyph: "😡", name: "angry face", keywords: ["mad", "angry", "rage"]),
        Emoji(glyph: "👍", name: "thumbs up", keywords: ["yes", "ok", "approve", "like"]),
        Emoji(glyph: "👎", name: "thumbs down", keywords: ["no", "dislike", "bad"]),
        Emoji(glyph: "🙏", name: "folded hands", keywords: ["please", "thanks", "pray"]),
        Emoji(glyph: "👏", name: "clapping hands", keywords: ["clap", "applause", "bravo"]),
        Emoji(glyph: "🙌", name: "raising hands", keywords: ["celebrate", "yay", "hooray"]),
        Emoji(glyph: "💪", name: "flexed biceps", keywords: ["strong", "muscle", "power"]),
        Emoji(glyph: "🔥", name: "fire", keywords: ["lit", "hot", "flame", "burn"]),
        Emoji(glyph: "✨", name: "sparkles", keywords: ["shine", "clean", "new", "magic"]),
        Emoji(glyph: "⭐", name: "star", keywords: ["favorite", "rating"]),
        Emoji(glyph: "🎉", name: "party popper", keywords: ["celebrate", "congrats", "party"]),
        Emoji(glyph: "❤️", name: "red heart", keywords: ["love", "like", "heart"]),
        Emoji(glyph: "💔", name: "broken heart", keywords: ["sad", "breakup"]),
        Emoji(glyph: "✅", name: "check mark", keywords: ["done", "yes", "correct", "ok"]),
        Emoji(glyph: "❌", name: "cross mark", keywords: ["no", "wrong", "delete", "cancel"]),
        Emoji(glyph: "⚠️", name: "warning", keywords: ["caution", "alert", "danger"]),
        Emoji(glyph: "💡", name: "light bulb", keywords: ["idea", "tip", "insight"]),
        Emoji(glyph: "🚀", name: "rocket", keywords: ["launch", "ship", "fast", "startup"]),
        Emoji(glyph: "🎯", name: "direct hit", keywords: ["target", "goal", "bullseye"]),
        Emoji(glyph: "🐛", name: "bug", keywords: ["bug", "defect", "insect"]),
        Emoji(glyph: "💻", name: "laptop", keywords: ["computer", "code", "work"]),
        Emoji(glyph: "📝", name: "memo", keywords: ["note", "write", "document", "edit"]),
        Emoji(glyph: "📌", name: "pushpin", keywords: ["pin", "location", "important"]),
        Emoji(glyph: "🔒", name: "locked", keywords: ["secure", "private", "lock"]),
        Emoji(glyph: "👀", name: "eyes", keywords: ["look", "watch", "see"]),
        Emoji(glyph: "🤝", name: "handshake", keywords: ["deal", "agree", "partner"]),
        Emoji(glyph: "🎵", name: "musical note", keywords: ["music", "song", "audio"]),
        Emoji(glyph: "☕", name: "coffee", keywords: ["coffee", "cafe", "break"]),
        Emoji(glyph: "🍕", name: "pizza", keywords: ["food", "pizza", "lunch"]),
        Emoji(glyph: "🌍", name: "globe", keywords: ["earth", "world", "global"]),
        Emoji(glyph: "⏰", name: "alarm clock", keywords: ["time", "alarm", "reminder"]),
        Emoji(glyph: "💯", name: "hundred points", keywords: ["100", "perfect", "score"]),
    ]

    func results(for query: String) -> [PaletteCommand] {
        let parts = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        guard let keyword = parts.first?.lowercased(), keyword == "emoji" || keyword == "e" else { return [] }
        let term = parts.count > 1 ? parts[1].lowercased() : ""

        let matches = term.isEmpty
            ? Array(Self.catalog.prefix(Self.maxResults))
            : Self.catalog.filter { emoji in
                emoji.name.contains(term) || emoji.keywords.contains { $0.contains(term) }
            }.prefix(Self.maxResults).map { $0 }

        return matches.map { emoji in
            PaletteCommand(
                id: UUID(),
                title: "\(emoji.glyph)  \(emoji.name)",
                subtitle: "↵ to copy \(emoji.glyph)",
                icon: .sfSymbol("face.smiling"),
                keywords: ["emoji"] + emoji.keywords,
                action: .execute { [copy] in copy(emoji.glyph) },
                category: "Emoji"
            )
        }
    }
}

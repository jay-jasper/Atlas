import Foundation

@MainActor
final class SubtitleService: ObservableObject {
    @Published var inputText: String = ""
    @Published var sourceFormat: SubtitleFormat = .srt
    @Published var targetFormat: SubtitleFormat = .vtt
    @Published var shiftMillis: Int = 0
    @Published private(set) var outputText: String = ""
    @Published private(set) var cueCount: Int = 0

    func process() {
        let cues = SubtitleDocument.parse(inputText, format: sourceFormat)
        cueCount = cues.count
        let shifted = SubtitleDocument.shift(cues, byMillis: shiftMillis)
        outputText = SubtitleDocument.serialize(shifted, format: targetFormat)
    }
}

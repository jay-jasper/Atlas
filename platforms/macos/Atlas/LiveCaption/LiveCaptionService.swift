import AVFoundation
import Foundation
import Speech

@MainActor
final class LiveCaptionService: ObservableObject {
    @Published private(set) var caption: String = ""
    @Published private(set) var isCaptioning = false
    @Published private(set) var statusMessage = ""

    private var buffer = CaptionBuffer()
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Applies a partial transcription (also used by tests).
    func applyPartial(_ text: String) {
        buffer.updatePartial(text)
        caption = buffer.displayText
    }

    /// Commits a final transcription segment (also used by tests).
    func applyFinal(_ text: String) {
        buffer.commit(text)
        caption = buffer.displayText
    }

    func start() {
        guard !isCaptioning else { return }
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard status == .authorized else {
                    self?.statusMessage = "Speech recognition permission required."
                    return
                }
                self?.beginRecognition()
            }
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isCaptioning = false
    }

    func clear() {
        buffer.clear()
        caption = ""
    }

    private func beginRecognition() {
        guard let recognizer, recognizer.isAvailable else {
            statusMessage = "Speech recognition unavailable."
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        do {
            try engine.start()
        } catch {
            statusMessage = "Could not start microphone."
            return
        }
        isCaptioning = true
        statusMessage = ""
        PrivacyPulseReporter.shared.microphone("Live Caption", detail: "Started live speech recognition")

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            Task { @MainActor in
                if result.isFinal {
                    self.applyFinal(result.bestTranscription.formattedString)
                } else {
                    self.applyPartial(result.bestTranscription.formattedString)
                }
            }
        }
    }
}

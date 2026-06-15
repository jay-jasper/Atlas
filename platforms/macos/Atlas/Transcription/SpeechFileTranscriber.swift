import Foundation
import Speech

/// A real file transcriber backed by Apple's on-device Speech framework.
/// Synchronous to satisfy the `Transcribing` protocol (it is called off the main
/// actor); it blocks on the async recognition result. The Whisper model selection
/// is accepted for API parity but Speech uses the system recognizer.
struct SpeechFileTranscriber: Transcribing {
    enum TranscribeError: Error { case unauthorized, unavailable, failed }

    func transcribe(fileURL: URL, model: WhisperModel) throws -> [TranscriptSegment] {
        guard authorize() else { throw TranscribeError.unauthorized }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw TranscribeError.unavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true

        let semaphore = DispatchSemaphore(value: 0)
        var collected: [SpeechTranscriptionMapper.Word] = []
        var failure: Error?

        let task = recognizer.recognitionTask(with: request) { result, error in
            if let error { failure = error; semaphore.signal(); return }
            guard let result, result.isFinal else { return }
            collected = result.bestTranscription.segments.map { seg in
                SpeechTranscriptionMapper.Word(
                    text: seg.substring,
                    startMs: Int(seg.timestamp * 1000),
                    endMs: Int((seg.timestamp + seg.duration) * 1000)
                )
            }
            semaphore.signal()
        }

        // Bound the wait so a stuck recognizer can't hang the job forever.
        if semaphore.wait(timeout: .now() + 120) == .timedOut {
            task.cancel()
            throw TranscribeError.failed
        }
        if failure != nil { throw TranscribeError.failed }
        return SpeechTranscriptionMapper.group(words: collected)
    }

    private func authorize() -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        let semaphore = DispatchSemaphore(value: 0)
        var granted = false
        SFSpeechRecognizer.requestAuthorization { status in
            granted = (status == .authorized)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        return granted
    }
}

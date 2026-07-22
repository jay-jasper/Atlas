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

struct WhisperModelStore {
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = support.appendingPathComponent("Atlas/WhisperModels", isDirectory: true)
        }
    }

    func url(for model: WhisperModel) -> URL {
        directory.appendingPathComponent("ggml-\(model.rawValue).bin")
    }

    func isInstalled(_ model: WhisperModel) -> Bool {
        guard let size = try? url(for: model).resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return false
        }
        return size > 1_000_000
    }

    func download(_ model: WhisperModel, completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        guard let remoteURL = URL(string: model.downloadURL), remoteURL.scheme == "https" else {
            completion(.failure(WhisperError.invalidDownload))
            return
        }
        URLSession.shared.downloadTask(with: remoteURL) { temporaryURL, _, error in
            do {
                if let error { throw error }
                guard let temporaryURL else { throw WhisperError.invalidDownload }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = url(for: model)
                let staged = destination.appendingPathExtension("download")
                try? FileManager.default.removeItem(at: staged)
                try FileManager.default.moveItem(at: temporaryURL, to: staged)
                let size = try staged.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 1_000_000 else {
                    try? FileManager.default.removeItem(at: staged)
                    throw WhisperError.invalidDownload
                }
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: staged, to: destination)
                completion(.success(destination))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

enum WhisperError: LocalizedError {
    case modelMissing
    case executableMissing
    case invalidDownload
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelMissing: "The selected Whisper model is not downloaded."
        case .executableMissing: "whisper-cli is not bundled or installed."
        case .invalidDownload: "The Whisper model download was invalid."
        case .transcriptionFailed(let message): "Whisper transcription failed: \(message)"
        }
    }
}

/// Local whisper.cpp CLI adapter used by the direct distribution. The command is
/// invoked without a shell, with bounded output and a two-hour hard timeout.
struct WhisperCLITranscriber: Transcribing {
    let modelStore: WhisperModelStore
    let commandRunner: SystemCommandRunning
    let executableCandidates: [URL]

    init(
        modelStore: WhisperModelStore = WhisperModelStore(),
        commandRunner: SystemCommandRunning = LiveSystemCommandRunner(timeout: 7_200),
        executableCandidates: [URL]? = nil
    ) {
        self.modelStore = modelStore
        self.commandRunner = commandRunner
        self.executableCandidates = executableCandidates ?? Self.defaultExecutableCandidates()
    }

    func transcribe(fileURL: URL, model: WhisperModel) throws -> [TranscriptSegment] {
        let modelURL = modelStore.url(for: model)
        guard modelStore.isInstalled(model) else { throw WhisperError.modelMissing }
        guard let executable = executableCandidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw WhisperError.executableMissing
        }

        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlas-whisper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let prefix = outputDirectory.appendingPathComponent("transcript")
        let result = try commandRunner.run(executable.path, arguments: [
            "-m", modelURL.path,
            "-f", fileURL.path,
            "-osrt",
            "-of", prefix.path,
        ])
        guard result.terminationStatus == 0 else {
            throw WhisperError.transcriptionFailed(result.standardError)
        }
        let srtURL = prefix.appendingPathExtension("srt")
        let text = try String(contentsOf: srtURL, encoding: .utf8)
        return SubtitleDocument.parse(text, format: .srt).map {
            TranscriptSegment(startMs: $0.start, endMs: $0.end, text: $0.text)
        }
    }

    private static func defaultExecutableCandidates() -> [URL] {
        var candidates: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("whisper-cli"))
        }
        candidates.append(contentsOf: [
            URL(fileURLWithPath: "/opt/homebrew/bin/whisper-cli"),
            URL(fileURLWithPath: "/usr/local/bin/whisper-cli"),
        ])
        return candidates
    }
}

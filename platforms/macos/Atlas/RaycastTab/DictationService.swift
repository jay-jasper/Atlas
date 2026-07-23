import AppKit
import AVFoundation
import Foundation
import Speech

/// 本地听写:SFSpeechRecognizer(优先端上识别)+ AVAudioEngine。
/// 浮动 HUD 展示实时转写;回车粘贴到前台,Esc 取消。
@MainActor
final class DictationService: NSObject, ObservableObject {
    static let shared = DictationService()

    @Published private(set) var transcript: String = ""
    @Published private(set) var isRecording = false
    @Published var lastError: String?

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    completion(false)
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async { completion(granted) }
                }
            }
        }
    }

    func start(locale: Locale = Locale(identifier: Locale.preferredLanguages.first ?? "zh-CN")) {
        guard !isRecording else { return }
        transcript = ""
        lastError = nil

        let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            lastError = loc("语音识别不可用", "Speech recognition unavailable")
            return
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            lastError = error.localizedDescription
            return
        }

        isRecording = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil {
                    self.finishRecording()
                }
            }
        }
    }

    /// 停止并返回最终文本。
    @discardableResult
    func stop() -> String {
        let final = transcript
        finishRecording()
        return final
    }

    func cancel() {
        transcript = ""
        finishRecording()
    }

    private func finishRecording() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
    }

    /// 粘贴听写结果到前台 app。
    func pasteTranscript() {
        let text = stop()
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        if let source = CGEventSource(stateID: .combinedSessionState) {
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down)
                event?.flags = .maskCommand
                event?.post(tap: .cgSessionEventTap)
            }
        }
    }
}

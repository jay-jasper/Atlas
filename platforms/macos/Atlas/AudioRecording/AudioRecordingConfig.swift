import AVFoundation
import Foundation

/// Output format for a recording. Settings/extension derivation is pure &
/// unit-testable.
enum AudioRecordingFormat: String, CaseIterable, Identifiable {
    case m4a
    case wav
    case caf

    var id: String { rawValue }

    var fileExtension: String { rawValue }

    var title: String {
        switch self {
        case .m4a: return "AAC (.m4a)"
        case .wav: return "WAV (.wav)"
        case .caf: return "CoreAudio (.caf)"
        }
    }

    var formatID: AudioFormatID {
        switch self {
        case .m4a: return kAudioFormatMPEG4AAC
        case .wav, .caf: return kAudioFormatLinearPCM
        }
    }
}

enum AudioRecordingConfig {
    /// AVAudioRecorder settings for a format + sample rate.
    static func settings(format: AudioRecordingFormat, sampleRate: Double = 44100, channels: Int = 1) -> [String: Any] {
        [
            AVFormatIDKey: format.formatID,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
    }

    /// Generates a timestamped filename, e.g. "Recording-1700000000.m4a".
    static func fileName(format: AudioRecordingFormat, timestamp: Int) -> String {
        "Recording-\(timestamp).\(format.fileExtension)"
    }
}

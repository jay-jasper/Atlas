import AVFoundation
import XCTest
@testable import Atlas

@MainActor
final class AudioRecordingConfigTests: XCTestCase {
    func testFileExtensions() {
        XCTAssertEqual(AudioRecordingFormat.m4a.fileExtension, "m4a")
        XCTAssertEqual(AudioRecordingFormat.wav.fileExtension, "wav")
        XCTAssertEqual(AudioRecordingFormat.caf.fileExtension, "caf")
    }

    func testFormatIDs() {
        XCTAssertEqual(AudioRecordingFormat.m4a.formatID, kAudioFormatMPEG4AAC)
        XCTAssertEqual(AudioRecordingFormat.wav.formatID, kAudioFormatLinearPCM)
    }

    func testSettingsContainsRequiredKeys() {
        let settings = AudioRecordingConfig.settings(format: .m4a, sampleRate: 48000, channels: 2)
        XCTAssertEqual(settings[AVSampleRateKey] as? Double, 48000)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 2)
        XCTAssertEqual(settings[AVFormatIDKey] as? AudioFormatID, kAudioFormatMPEG4AAC)
    }

    func testFileName() {
        XCTAssertEqual(AudioRecordingConfig.fileName(format: .wav, timestamp: 1700000000), "Recording-1700000000.wav")
    }

    func testServiceNextOutputURLIsDeterministic() {
        let dir = URL(fileURLWithPath: "/tmp/recordings")
        let service = AudioRecordingService(outputDirectory: dir, clock: { 42 })
        service.format = .m4a
        XCTAssertEqual(service.nextOutputURL().path, "/tmp/recordings/Recording-42.m4a")
    }
}

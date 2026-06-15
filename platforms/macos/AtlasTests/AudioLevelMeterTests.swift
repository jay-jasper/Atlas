import XCTest
@testable import Atlas

@MainActor
final class AudioLevelMeterTests: XCTestCase {
    func testSilenceIsFloor() {
        XCTAssertEqual(AudioLevelMeter.dBFS(rms: 0), -80)
        XCTAssertEqual(AudioLevelMeter.level(rms: 0), 0, accuracy: 0.001)
    }

    func testFullScale() {
        XCTAssertEqual(AudioLevelMeter.dBFS(rms: 1.0), 0, accuracy: 0.001)
        XCTAssertEqual(AudioLevelMeter.level(rms: 1.0), 1, accuracy: 0.001)
    }

    func testHalfAmplitudeIsAboutMinus6dB() {
        XCTAssertEqual(AudioLevelMeter.dBFS(rms: 0.5), -6.02, accuracy: 0.05)
    }

    func testNormalizedClampsToRange() {
        XCTAssertEqual(AudioLevelMeter.normalized(dBFS: 10), 1, accuracy: 0.001)
        XCTAssertEqual(AudioLevelMeter.normalized(dBFS: -100), 0, accuracy: 0.001)
        XCTAssertEqual(AudioLevelMeter.normalized(dBFS: -40), 0.5, accuracy: 0.001)
    }

    func testRMS() {
        XCTAssertEqual(AudioLevelMeter.rms(samples: [1, -1, 1, -1]), 1, accuracy: 0.001)
        XCTAssertEqual(AudioLevelMeter.rms(samples: []), 0)
    }

    func testServiceIngest() {
        let service = AudioMeterService()
        service.ingest(samples: [1, -1, 1, -1]) // full-scale RMS
        XCTAssertEqual(service.level, 1, accuracy: 0.001)
        XCTAssertEqual(service.peakDB, 0, accuracy: 0.001)
    }
}

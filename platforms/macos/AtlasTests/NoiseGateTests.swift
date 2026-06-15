import XCTest
@testable import Atlas

@MainActor
final class NoiseGateTests: XCTestCase {
    func testPassesLoudAudioUnchanged() {
        let gate = NoiseGate(threshold: 0.1, floorGain: 0)
        let loud: [Float] = [0.5, -0.5, 0.5, -0.5] // RMS 0.5 > threshold
        XCTAssertEqual(gate.process(loud), loud)
        XCTAssertTrue(gate.isOpen(rms: 0.5))
    }

    func testMutesQuietAudio() {
        let gate = NoiseGate(threshold: 0.1, floorGain: 0)
        let quiet: [Float] = [0.01, -0.01, 0.01, -0.01] // RMS 0.01 < threshold
        XCTAssertEqual(gate.process(quiet), [0, 0, 0, 0])
        XCTAssertFalse(gate.isOpen(rms: 0.01))
    }

    func testFloorGainAttenuatesRatherThanMutes() {
        let gate = NoiseGate(threshold: 0.1, floorGain: 0.5)
        let quiet: [Float] = [0.02, -0.02]
        XCTAssertEqual(gate.process(quiet), [0.01, -0.01])
    }

    func testRMS() {
        XCTAssertEqual(NoiseGate.rms([1, -1, 1, -1]), 1, accuracy: 0.001)
        XCTAssertEqual(NoiseGate.rms([]), 0)
    }

    func testServicePassthroughWhenDisabled() {
        let service = NoiseGateService()
        service.threshold = 0.1
        service.isEnabled = false
        let quiet: [Float] = [0.01, -0.01]
        XCTAssertEqual(service.process(quiet), quiet) // not gated when disabled
        XCTAssertFalse(service.isGateOpen)
    }

    func testServiceGatesWhenEnabled() {
        let service = NoiseGateService()
        service.threshold = 0.1
        service.isEnabled = true
        XCTAssertEqual(service.process([0.01, -0.01]), [0, 0])
    }
}

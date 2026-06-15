import XCTest
@testable import Atlas

@MainActor
final class ScrollSmoothingEngineTests: XCTestCase {
    func testConvergesToTotalDelta() {
        var engine = ScrollSmoothingEngine(smoothing: 0.8, step: 1.0)
        engine.addDelta(100)
        var total = 0.0
        var frames = 0
        while engine.isAnimating && frames < 1000 {
            total += engine.nextFrame()
            frames += 1
        }
        XCTAssertEqual(total, 100, accuracy: 0.001)
        XCTAssertFalse(engine.isAnimating)
    }

    func testFirstFrameRespectsSmoothing() {
        var engine = ScrollSmoothingEngine(smoothing: 0.9, step: 1.0)
        engine.addDelta(100)
        // First step ~ remaining * (1 - smoothing) = 10.
        XCTAssertEqual(engine.nextFrame(), 10, accuracy: 0.001)
    }

    func testStepMultipliesDelta() {
        var engine = ScrollSmoothingEngine(smoothing: 0, step: 2.0)
        engine.addDelta(10)
        // No smoothing: flushes the accelerated total immediately.
        XCTAssertEqual(engine.nextFrame(), 20, accuracy: 0.001)
    }

    func testAccumulatesMultipleDeltas() {
        var engine = ScrollSmoothingEngine(smoothing: 0.5, step: 1.0)
        engine.addDelta(50)
        engine.addDelta(50)
        var total = 0.0
        while engine.isAnimating { total += engine.nextFrame() }
        XCTAssertEqual(total, 100, accuracy: 0.001)
    }

    func testZeroWhenIdle() {
        var engine = ScrollSmoothingEngine()
        XCTAssertEqual(engine.nextFrame(), 0)
    }

    func testServiceProcessPipeline() {
        let service = ScrollSmoothingService()
        service.smoothing = 0
        service.step = 1
        XCTAssertEqual(service.process(delta: 5), 5, accuracy: 0.001)
    }
}

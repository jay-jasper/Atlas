import XCTest
@testable import Atlas

@MainActor
final class CalculatorCommandProviderTests: XCTestCase {
    private final class StubCurrency: CurrencyRateProviding {
        var stub: (rate: Double, age: TimeInterval)?
        private(set) var refreshCount = 0
        func cachedRate(from: String, to: String) -> (rate: Double, age: TimeInterval)? { stub }
        func refreshIfNeeded() { refreshCount += 1 }
    }

    private func makeProvider(
        currency: CurrencyRateProviding = StubCurrency(),
        copied: @escaping (String) -> Void = { _ in }
    ) -> CalculatorCommandProvider {
        CalculatorCommandProvider(
            evaluator: NativeExpressionEvaluator(),
            currency: currency,
            copyToPasteboard: copied
        )
    }

    func testMathResult() {
        let results = makeProvider().results(for: "12 * 34 + 5")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "= 413")
        XCTAssertEqual(results[0].category, "Calculator")
    }

    func testUnitResult() {
        let results = makeProvider().results(for: "5 km to miles")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].title.hasPrefix("= 3.10"))
        XCTAssertEqual(results[0].category, "Unit")
    }

    func testNonExpressionYieldsNoResults() {
        XCTAssertTrue(makeProvider().results(for: "screenshot").isEmpty)
    }

    func testCurrencyWithCache() {
        let stub = StubCurrency()
        stub.stub = (rate: 7.2, age: 60)
        let results = makeProvider(currency: stub).results(for: "100 USD to CNY")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "= 720 CNY")
        XCTAssertEqual(stub.refreshCount, 1)
    }

    func testCurrencyStaleLabel() {
        let stub = StubCurrency()
        stub.stub = (rate: 7.2, age: 1380) // 23 minutes
        let results = makeProvider(currency: stub).results(for: "100 USD to CNY")
        XCTAssertTrue(results[0].subtitle?.contains("23 minutes ago") ?? false)
    }

    func testCurrencyNoCacheShowsUnavailable() {
        let stub = StubCurrency()
        stub.stub = nil
        let results = makeProvider(currency: stub).results(for: "100 USD to CNY")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].subtitle?.contains("unavailable") ?? false)
    }

    func testExecutingMathCopiesResult() {
        var copied: [String] = []
        let results = makeProvider(copied: { copied.append($0) }).results(for: "2 + 2")
        if case .execute(let run)? = results.first?.action {
            run()
        } else {
            XCTFail("expected execute action")
        }
        XCTAssertEqual(copied, ["4"])
    }
}

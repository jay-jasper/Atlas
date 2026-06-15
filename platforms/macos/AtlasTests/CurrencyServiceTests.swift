import XCTest
@testable import Atlas

@MainActor
final class CurrencyServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "atlas.currency.tests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testCacheMissReturnsNil() {
        let service = CurrencyService(defaults: defaults)
        XCTAssertNil(service.cachedRate(from: "USD", to: "CNY"))
    }

    func testCacheHitComputesCrossRate() {
        // USD-based table: 1 USD = 7.2 CNY, 1 USD = 0.92 EUR.
        defaults.set(["USD": 1.0, "CNY": 7.2, "EUR": 0.92], forKey: "atlas.currency.rates")
        defaults.set(Date().timeIntervalSince1970, forKey: "atlas.currency.timestamp")
        let service = CurrencyService(defaults: defaults)

        let usdToCny = try? XCTUnwrap(service.cachedRate(from: "USD", to: "CNY"))
        XCTAssertEqual(usdToCny?.rate ?? 0, 7.2, accuracy: 1e-6)

        let eurToCny = try? XCTUnwrap(service.cachedRate(from: "EUR", to: "CNY"))
        XCTAssertEqual(eurToCny?.rate ?? 0, 7.2 / 0.92, accuracy: 1e-6)
    }

    func testStaleAgeIsReported() {
        defaults.set(["USD": 1.0, "CNY": 7.2], forKey: "atlas.currency.rates")
        defaults.set(Date().timeIntervalSince1970 - 1800, forKey: "atlas.currency.timestamp")
        let service = CurrencyService(defaults: defaults)

        let result = try? XCTUnwrap(service.cachedRate(from: "USD", to: "CNY"))
        XCTAssertGreaterThan(result?.age ?? 0, 1700)
    }

    func testUnknownCodeReturnsNil() {
        defaults.set(["USD": 1.0, "CNY": 7.2], forKey: "atlas.currency.rates")
        defaults.set(Date().timeIntervalSince1970, forKey: "atlas.currency.timestamp")
        let service = CurrencyService(defaults: defaults)
        XCTAssertNil(service.cachedRate(from: "USD", to: "XXX"))
    }
}

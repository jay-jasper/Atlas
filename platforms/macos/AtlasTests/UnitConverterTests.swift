import XCTest
@testable import Atlas

@MainActor
final class UnitConverterTests: XCTestCase {
    func testLength() {
        XCTAssertEqual(try XCTUnwrap(UnitConverter.convert(5, from: "km", to: "miles")), 3.10686, accuracy: 1e-4)
        XCTAssertEqual(try XCTUnwrap(UnitConverter.convert(100, from: "cm", to: "m")), 1, accuracy: 1e-9)
    }

    func testWeight() {
        XCTAssertEqual(try XCTUnwrap(UnitConverter.convert(1, from: "kg", to: "lbs")), 2.20462, accuracy: 1e-4)
    }

    func testTemperatureCelsiusToFahrenheit() {
        XCTAssertEqual(try XCTUnwrap(UnitConverter.convert(100, from: "c", to: "f")), 212, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(UnitConverter.convert(0, from: "c", to: "k")), 273.15, accuracy: 1e-6)
    }

    func testStorage() {
        XCTAssertEqual(try XCTUnwrap(UnitConverter.convert(1, from: "gb", to: "mb")), 1024, accuracy: 1e-6)
    }

    func testSpeed() {
        XCTAssertEqual(try XCTUnwrap(UnitConverter.convert(36, from: "km/h", to: "m/s")), 10, accuracy: 1e-6)
    }

    func testRoundTrip() {
        let original = 42.0
        let toMiles = try! XCTUnwrap(UnitConverter.convert(original, from: "km", to: "miles"))
        let back = try! XCTUnwrap(UnitConverter.convert(toMiles, from: "miles", to: "km"))
        XCTAssertEqual(back, original, accuracy: 1e-6)
    }

    func testAliases() {
        XCTAssertNotNil(UnitConverter.convert(1, from: "kilometers", to: "meters"))
        XCTAssertEqual(UnitConverter.canonicalUnit("pounds"), "lbs")
    }

    func testMismatchedCategoriesReturnNil() {
        XCTAssertNil(UnitConverter.convert(1, from: "km", to: "kg"))
    }

    func testUnknownUnitReturnsNil() {
        XCTAssertNil(UnitConverter.convert(1, from: "furlongs", to: "km"))
        XCTAssertNil(UnitConverter.canonicalUnit("furlongs"))
    }
}

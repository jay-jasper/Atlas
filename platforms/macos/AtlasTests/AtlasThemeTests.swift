import SwiftUI
import XCTest
@testable import Atlas

@MainActor
final class AtlasThemeTests: XCTestCase {
    func testHexParsing() {
        XCTAssertEqual(Color(hex: "3FC4AF").rgb255.map { [$0.r, $0.g, $0.b] }, [63, 196, 175])
        XCTAssertEqual(Color(hex: "#1F8579").rgb255.map { [$0.r, $0.g, $0.b] }, [31, 133, 121])
        XCTAssertEqual(Color(hex: "000000").rgb255.map { [$0.r, $0.g, $0.b] }, [0, 0, 0])
        XCTAssertEqual(Color(hex: "FFFFFF").rgb255.map { [$0.r, $0.g, $0.b] }, [255, 255, 255])
    }

    func testDarkAccentMatchesPrototype() {
        // Prototype --accent (dark) = #3FC4AF.
        XCTAssertEqual(AtlasTheme.dark.accent.rgb255.map { [$0.r, $0.g, $0.b] }, [63, 196, 175])
        XCTAssertEqual(AtlasTheme.dark.red.rgb255.map { [$0.r, $0.g, $0.b] }, [255, 107, 107])
        XCTAssertEqual(AtlasTheme.dark.blue.rgb255.map { [$0.r, $0.g, $0.b] }, [94, 169, 255])
    }

    func testLightAccentMatchesPrototype() {
        // Prototype --accent (light) = #1F8579.
        XCTAssertEqual(AtlasTheme.light.accent.rgb255.map { [$0.r, $0.g, $0.b] }, [31, 133, 121])
        XCTAssertEqual(AtlasTheme.light.green.rgb255.map { [$0.r, $0.g, $0.b] }, [46, 159, 79])
    }

    func testResolveBySchemePicksVariant() {
        XCTAssertEqual(AtlasTheme.resolve(for: .dark), .dark)
        XCTAssertEqual(AtlasTheme.resolve(for: .light), .light)
    }
}

import XCTest
@testable import Atlas

final class MenuPanelRowMappingTests: XCTestCase {
    // Chevron rows are built by mapping `orderedPrimarySections()` directly
    // (ContentView.menuPanelGroups), so every enabled section is covered by
    // construction. These tests lock the public registries the panel renders.

    func testAllWidgetKindsDescribed() {
        XCTAssertEqual(WidgetKind.allCases.count, 5)
        for kind in WidgetKind.allCases {
            XCTAssertFalse(kind.title.isEmpty)
            XCTAssertFalse(kind.icon.isEmpty)
            XCTAssertFalse(kind.summary.isEmpty)
        }
    }

    func testNetworkRateFormatting() {
        XCTAssertEqual(NetworkWidget.rateText(nil), "-- KB/s")
        XCTAssertEqual(NetworkWidget.rateText(512_000), "512 KB/s")
        XCTAssertEqual(NetworkWidget.rateText(2_500_000), "2.5 MB/s")
    }
}

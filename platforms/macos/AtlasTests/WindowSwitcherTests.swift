import XCTest
@testable import Atlas

@MainActor
final class WindowSwitcherTests: XCTestCase {
    private func win(_ id: Int, _ app: String, layer: Int = 0, minimized: Bool = false) -> SwitchableWindow {
        SwitchableWindow(id: id, appName: app, title: "t\(id)", isMinimized: minimized, layer: layer)
    }

    func testFiltersNonNormalLayersAndMinimized() {
        let switcher = WindowSwitcher(windows: [
            win(1, "Safari"),
            win(2, "Menubar", layer: 25),
            win(3, "Notes", minimized: true),
            win(4, "", layer: 0),
            win(5, "Xcode"),
        ])
        XCTAssertEqual(switcher.windows.map(\.appName), ["Safari", "Xcode"])
    }

    func testInitialSelectionIsSecondWindow() {
        // Alt-Tab convention: highlight the previous window first.
        let switcher = WindowSwitcher(windows: [win(1, "A"), win(2, "B")])
        XCTAssertEqual(switcher.selected?.appName, "B")
    }

    func testCycleWraps() {
        var switcher = WindowSwitcher(windows: [win(1, "A"), win(2, "B"), win(3, "C")])
        switcher.cycle(forward: true) // B(1) -> C(2)
        XCTAssertEqual(switcher.selected?.appName, "C")
        switcher.cycle(forward: true) // C -> A (wrap)
        XCTAssertEqual(switcher.selected?.appName, "A")
        switcher.cycle(forward: false) // A -> C (wrap back)
        XCTAssertEqual(switcher.selected?.appName, "C")
    }

    func testSelectByID() {
        var switcher = WindowSwitcher(windows: [win(1, "A"), win(2, "B"), win(3, "C")])
        switcher.select(id: 1)
        XCTAssertEqual(switcher.selected?.id, 1)
    }

    func testEmptyIsSafe() {
        var switcher = WindowSwitcher(windows: [])
        switcher.cycle(forward: true)
        XCTAssertNil(switcher.selected)
    }
}

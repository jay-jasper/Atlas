import XCTest
@testable import Atlas

@MainActor
final class MenuPanelStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "MenuPanelStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testDefaultsToGaugesAndNetwork() {
        XCTAssertEqual(WidgetStore(defaults: defaults).enabled, [.gauges, .network])
    }

    func testAddRemovePersist() {
        let store = WidgetStore(defaults: defaults)
        store.add(.calendar)
        store.add(.calendar) // idempotent
        store.remove(.network)

        let reloaded = WidgetStore(defaults: defaults)
        XCTAssertEqual(reloaded.enabled, [.gauges, .calendar])
    }

    func testMoveUpDown() {
        let store = WidgetStore(defaults: defaults)
        store.add(.calendar)
        store.moveUp(.calendar)
        XCTAssertEqual(store.enabled, [.gauges, .calendar, .network])
        store.moveUp(.gauges) // no-op at top
        XCTAssertEqual(store.enabled.first, .gauges)
        store.moveDown(.calendar)
        XCTAssertEqual(store.enabled, [.gauges, .network, .calendar])
        store.moveDown(.calendar) // no-op at bottom
        XCTAssertEqual(store.enabled.last, .calendar)
    }

    func testGarbageFallsBackToDefault() {
        defaults.set(Data("junk".utf8), forKey: "menuPanel.widgets")
        XCTAssertEqual(WidgetStore(defaults: defaults).enabled, [.gauges, .network])
    }
}

final class LunarCalendarTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var components = DateComponents()
        components.year = y
        components.month = m
        components.day = d
        components.hour = 12
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    func testKnownLunarDays() {
        // 2026-06-13 is 廿八 (per MacTools reference screenshot).
        XCTAssertEqual(LunarCalendar.dayLabel(for: date(2026, 6, 13)), "廿八")
        // 2026-06-15 is 五月初一 → shows the month name.
        XCTAssertEqual(LunarCalendar.dayLabel(for: date(2026, 6, 15)), "五月")
        // 2026-06-19 is 端午 (五月初五).
        XCTAssertEqual(LunarCalendar.dayLabel(for: date(2026, 6, 19)), "初五")
    }
}

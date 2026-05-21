import XCTest
@testable import Atlas

final class WindowManagementProviderTests: XCTestCase {
    func testEmptyQueryReturnsNoResults() {
        let provider = makeProvider()

        XCTAssertTrue(provider.results(for: " \n ").isEmpty)
    }

    func testWindowQueryReturnsWindowManagementCommandsInOrder() {
        let provider = makeProvider()
        let results = provider.results(for: "window")

        XCTAssertEqual(results.map(\.title), [
            "Center Frontmost Window",
            "Move Frontmost Window Left Half",
            "Move Frontmost Window Right Half",
            "Maximize Frontmost Window",
        ])
    }

    func testLeftQueryReturnsOnlyLeftHalfCommand() {
        let provider = makeProvider()
        let results = provider.results(for: "left")

        XCTAssertEqual(results.map(\.title), ["Move Frontmost Window Left Half"])
    }

    func testRightQueryReturnsOnlyRightHalfCommand() {
        let provider = makeProvider()
        let results = provider.results(for: "right")

        XCTAssertEqual(results.map(\.title), ["Move Frontmost Window Right Half"])
    }

    func testMaximizeQueryReturnsOnlyMaximizeCommand() {
        let provider = makeProvider()
        let results = provider.results(for: "maximize")

        XCTAssertEqual(results.map(\.title), ["Maximize Frontmost Window"])
    }

    func testAllWindowResultsHaveWindowCategoryAndWindowIcon() {
        let provider = makeProvider()
        let results = provider.results(for: "window")

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.category == "Window" })
        XCTAssertTrue(results.allSatisfy { $0.icon == .sfSymbol("rectangle.inset.filled") })
    }

    func testExecutingLeftResultCallsWindowManager() {
        let windowManager = FakeWindowManager()
        let provider = makeProvider(windowManager: windowManager)

        let result = provider.results(for: "left").first
        if case .execute(let execute)? = result?.action {
            execute()
        } else {
            XCTFail("expected executable window management result")
        }

        XCTAssertEqual(windowManager.performedActions, [.leftHalf])
    }

    func testResultsAreCappedToFixedSmallCount() {
        let provider = makeProvider(actions: [
            .center,
            .leftHalf,
            .rightHalf,
            .maximize,
            .center,
            .leftHalf,
        ])
        let results = provider.results(for: "window")

        XCTAssertLessThanOrEqual(results.count, 5)
    }

    private func makeProvider(
        windowManager: WindowManaging = FakeWindowManager(),
        actions: [WindowManagementAction] = WindowManagementAction.allCases
    ) -> WindowManagementProvider {
        WindowManagementProvider(windowManager: windowManager, actions: actions)
    }
}

private final class FakeWindowManager: WindowManaging {
    private(set) var performedActions: [WindowManagementAction] = []

    @discardableResult
    func perform(_ action: WindowManagementAction) -> Bool {
        performedActions.append(action)
        return true
    }
}

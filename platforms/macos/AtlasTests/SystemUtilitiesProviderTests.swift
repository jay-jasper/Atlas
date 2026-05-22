import XCTest
@testable import Atlas

final class SystemUtilitiesProviderTests: XCTestCase {
    func testDisabledFeatureReturnsNoCommands() {
        let provider = SystemUtilitiesProvider(
            isEnabled: { false },
            onToggleKeepAwake: {},
            onTogglePresentationMode: {},
            onOpenHandMirror: {},
            onRefreshDisplays: {}
        )

        XCTAssertEqual(provider.results(for: "awake").count, 0)
    }

    func testEnabledFeatureReturnsUtilityCommands() {
        let provider = SystemUtilitiesProvider(
            isEnabled: { true },
            onToggleKeepAwake: {},
            onTogglePresentationMode: {},
            onOpenHandMirror: {},
            onRefreshDisplays: {}
        )

        let titles = provider.results(for: "system").map(\.title)

        XCTAssertEqual(titles, [
            "Keep Mac Awake",
            "Presentation Mode",
            "Hand Mirror",
            "Refresh Display Capabilities",
        ])
    }

    func testCommandInvokesAction() {
        var callCount = 0
        let provider = SystemUtilitiesProvider(
            isEnabled: { true },
            onToggleKeepAwake: { callCount += 1 },
            onTogglePresentationMode: {},
            onOpenHandMirror: {},
            onRefreshDisplays: {}
        )

        guard case let .execute(action) = provider.results(for: "awake").first?.action else {
            return XCTFail("Expected execute action")
        }
        action()

        XCTAssertEqual(callCount, 1)
    }
}

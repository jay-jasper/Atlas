import XCTest
@testable import Atlas

@MainActor
final class SystemUtilitiesPanelTests: XCTestCase {
    func testPanelActionsAreCallable() {
        var keepAwakeStartCount = 0
        var presentationStartCount = 0
        var mirrorOpenCount = 0
        var refreshCount = 0

        let model = SystemUtilitiesPanelModel(
            state: .initial,
            onToggleKeepAwake: { keepAwakeStartCount += 1 },
            onTogglePresentationMode: { presentationStartCount += 1 },
            onOpenHandMirror: { mirrorOpenCount += 1 },
            onRefreshDisplays: { refreshCount += 1 }
        )

        model.onToggleKeepAwake()
        model.onTogglePresentationMode()
        model.onOpenHandMirror()
        model.onRefreshDisplays()

        XCTAssertEqual(keepAwakeStartCount, 1)
        XCTAssertEqual(presentationStartCount, 1)
        XCTAssertEqual(mirrorOpenCount, 1)
        XCTAssertEqual(refreshCount, 1)
    }
}

import XCTest

final class AtlasUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testApplicationLaunchesAsMenuBarAgent() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10) || app.state == .runningBackground)
        app.terminate()
    }
}

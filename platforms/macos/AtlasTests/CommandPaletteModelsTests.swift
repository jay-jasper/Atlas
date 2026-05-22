import XCTest
@testable import Atlas

final class CommandPaletteModelsTests: XCTestCase {
    func testPaletteCommandHasStableIdentity() {
        let id = UUID()
        let cmd = PaletteCommand(
            id: id,
            title: "Capture Area",
            subtitle: nil,
            icon: .sfSymbol("camera"),
            keywords: ["screenshot"],
            action: .execute({}),
            category: "Atlas"
        )
        XCTAssertEqual(cmd.id, id)
        XCTAssertEqual(cmd.title, "Capture Area")
        XCTAssertNil(cmd.subtitle)
        XCTAssertEqual(cmd.category, "Atlas")
        XCTAssertEqual(cmd.keywords, ["screenshot"])
    }

    func testPaletteIconEquality() {
        XCTAssertEqual(PaletteIcon.sfSymbol("camera"), PaletteIcon.sfSymbol("camera"))
        XCTAssertNotEqual(PaletteIcon.sfSymbol("camera"), PaletteIcon.sfSymbol("photo"))
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        XCTAssertEqual(PaletteIcon.appIcon(url), PaletteIcon.appIcon(url))
    }

    func testPaletteActionIsExecuteOrPush() {
        var called = false
        let exec = PaletteAction.execute({ called = true })
        if case .execute(let fn) = exec { fn() }
        XCTAssertTrue(called)

        let push = PaletteAction.push(.portLookup)
        if case .push(let dest) = push {
            XCTAssertEqual(dest, PaletteDestination.portLookup)
        } else {
            XCTFail("expected .push")
        }
    }

    func testPaletteDestinationEquality() {
        let command = CustomAutomationCommand(title: "Deploy", command: "echo deploy", kind: .shell)
        let skill = SkillDefinition.screenshotSummaryExample(now: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(PaletteDestination.portLookup, PaletteDestination.portLookup)
        XCTAssertEqual(PaletteDestination.windowPicker, PaletteDestination.windowPicker)
        XCTAssertEqual(PaletteDestination.screenshotLibrary, PaletteDestination.screenshotLibrary)
        XCTAssertEqual(PaletteDestination.automationOutput(command), PaletteDestination.automationOutput(command))
        XCTAssertEqual(PaletteDestination.skillRun(skill), PaletteDestination.skillRun(skill))
        XCTAssertNotEqual(PaletteDestination.portLookup, PaletteDestination.windowPicker)
    }
}

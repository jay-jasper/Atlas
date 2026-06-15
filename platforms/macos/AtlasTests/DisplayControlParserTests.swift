import XCTest
@testable import Atlas

@MainActor
final class DisplayControlParserTests: XCTestCase {
    func testParseSingleDDCDisplay() {
        let displays = DisplayControlParser.parse("Display 1: LG UltraFine DDC/CI supported\n")
        XCTAssertEqual(displays.count, 1)
        XCTAssertEqual(displays[0].name, "LG UltraFine")
        XCTAssertTrue(displays[0].supportsDDC)
        XCTAssertFalse(displays[0].isBuiltin)
        XCTAssertEqual(displays[0].ddcIndex, 1)
    }

    func testParseBuiltinAndExternalDisplay() {
        let output = "Display 1: Built-in Retina\nDisplay 2: Dell U2720Q DDC/CI supported\n"
        let displays = DisplayControlParser.parse(output)
        XCTAssertEqual(displays.count, 2)
        XCTAssertTrue(displays[0].isBuiltin)
        XCTAssertFalse(displays[0].supportsDDC)
        XCTAssertEqual(displays[0].ddcIndex, 1)
        XCTAssertFalse(displays[1].isBuiltin)
        XCTAssertTrue(displays[1].supportsDDC)
        XCTAssertEqual(displays[1].ddcIndex, 2)
    }

    func testParseEmptyOutputReturnsEmpty() {
        XCTAssertTrue(DisplayControlParser.parse("").isEmpty)
    }

    func testParseBrightnessCurrentEqualsFormat() {
        XCTAssertEqual(DisplayControlParser.parseBrightness("D: [10] current=75, max=100"), 75)
    }

    func testParseBrightnessColonFormat() {
        XCTAssertEqual(DisplayControlParser.parseBrightness("D: [10] brightness: 50"), 50)
    }

    func testParseBrightnessCurrentColonFormat() {
        XCTAssertEqual(DisplayControlParser.parseBrightness("VCP code 0x10: current: 80, max: 100"), 80)
    }

    func testParseBrightnessReturnsNilForGarbage() {
        XCTAssertNil(DisplayControlParser.parseBrightness("no brightness here"))
    }

    func testSetBrightnessStoresValueAndRunsCommand() throws {
        let probe = FakeDisplayCapabilityProbe(result: SystemCommandResult(
            terminationStatus: 0,
            standardOutput: "Display 1: LG UltraFine DDC/CI supported\n",
            standardError: ""
        ))
        let runner = SpySystemCommandRunner()
        let service = DisplayControlService(probe: probe, commandRunner: runner)
        let displays = try service.refreshDisplays()

        service.setBrightness(for: displays[0], to: 80)

        XCTAssertEqual(service.brightnessLevels["display-1"], 80)
        XCTAssertEqual(runner.lastArguments, ["ddcctl", "-d", "1", "-b", "80"])
    }

    func testSetBrightnessClampsBelowZero() throws {
        let probe = FakeDisplayCapabilityProbe(result: SystemCommandResult(
            terminationStatus: 0,
            standardOutput: "Display 1: LG UltraFine DDC/CI supported\n",
            standardError: ""
        ))
        let service = DisplayControlService(probe: probe, commandRunner: SpySystemCommandRunner())
        let displays = try service.refreshDisplays()

        service.setBrightness(for: displays[0], to: -10)
        XCTAssertEqual(service.brightnessLevels["display-1"], 0)
    }

    func testSetBrightnessClampsAbove100() throws {
        let probe = FakeDisplayCapabilityProbe(result: SystemCommandResult(
            terminationStatus: 0,
            standardOutput: "Display 1: LG UltraFine DDC/CI supported\n",
            standardError: ""
        ))
        let service = DisplayControlService(probe: probe, commandRunner: SpySystemCommandRunner())
        let displays = try service.refreshDisplays()

        service.setBrightness(for: displays[0], to: 150)
        XCTAssertEqual(service.brightnessLevels["display-1"], 100)
    }
}

final class SpySystemCommandRunner: SystemCommandRunning {
    private(set) var lastExecutable: String = ""
    private(set) var lastArguments: [String] = []

    func run(_ executable: String, arguments: [String]) throws -> SystemCommandResult {
        lastExecutable = executable
        lastArguments = arguments
        return SystemCommandResult(terminationStatus: 0, standardOutput: "", standardError: "")
    }

    func start(_ executable: String, arguments: [String]) throws -> SystemCommandProcess {
        lastExecutable = executable
        lastArguments = arguments
        return SpySystemCommandProcess()
    }
}

final class SpySystemCommandProcess: SystemCommandProcess {
    private(set) var isRunning = false
    func terminate() { isRunning = false }
}

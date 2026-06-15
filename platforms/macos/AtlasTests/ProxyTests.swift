import XCTest
@testable import Atlas

@MainActor
final class ProxyCommandBuilderTests: XCTestCase {
    func testHTTPSetCommand() {
        let profile = ProxyProfile(name: "Work", kind: .http, host: "127.0.0.1", port: 8080)
        XCTAssertEqual(
            ProxyCommandBuilder.setCommand(profile, networkService: "Wi-Fi"),
            ["-setwebproxy", "Wi-Fi", "127.0.0.1", "8080"]
        )
    }

    func testSocksSetCommand() {
        let profile = ProxyProfile(name: "VPN", kind: .socks, host: "10.0.0.1", port: 1080)
        XCTAssertEqual(
            ProxyCommandBuilder.setCommand(profile, networkService: "Wi-Fi"),
            ["-setsocksfirewallproxy", "Wi-Fi", "10.0.0.1", "1080"]
        )
    }

    func testEnableCommands() {
        XCTAssertEqual(
            ProxyCommandBuilder.enableCommand(.https, networkService: "Wi-Fi", on: true),
            ["-setsecurewebproxystate", "Wi-Fi", "on"]
        )
        XCTAssertEqual(
            ProxyCommandBuilder.enableCommand(.http, networkService: "Ethernet", on: false),
            ["-setwebproxystate", "Ethernet", "off"]
        )
    }

    func testValidity() {
        XCTAssertTrue(ProxyProfile(name: "x", kind: .http, host: "h", port: 80).isValid)
        XCTAssertFalse(ProxyProfile(name: "", kind: .http, host: "h", port: 80).isValid)
        XCTAssertFalse(ProxyProfile(name: "x", kind: .http, host: "h", port: 0).isValid)
    }
}

private final class RecordingRunner: SystemCommandRunning {
    private(set) var commands: [[String]] = []
    func run(_ executable: String, arguments: [String]) throws -> SystemCommandResult {
        commands.append(arguments)
        return SystemCommandResult(terminationStatus: 0, standardOutput: "", standardError: "")
    }
    func start(_ executable: String, arguments: [String]) throws -> SystemCommandProcess {
        ProxyStubProcess()
    }
}

private final class ProxyStubProcess: SystemCommandProcess {
    var isRunning = false
    func terminate() {}
}

@MainActor
final class ProxyServiceTests: XCTestCase {
    func testApplyRunsSetThenEnable() {
        let runner = RecordingRunner()
        let service = ProxyService(store: InMemoryProxyProfileStore(), runner: runner)
        let profile = ProxyProfile(name: "Work", kind: .http, host: "127.0.0.1", port: 8080)
        service.add(profile)
        service.apply(profile)

        XCTAssertEqual(service.activeProfileID, profile.id)
        XCTAssertEqual(runner.commands.count, 2)
        XCTAssertEqual(runner.commands[0].first, "-setwebproxy")
        XCTAssertEqual(runner.commands[1], ["-setwebproxystate", "Wi-Fi", "on"])
    }

    func testDisableAllTurnsOffEveryKind() {
        let runner = RecordingRunner()
        let service = ProxyService(store: InMemoryProxyProfileStore(), runner: runner)
        service.disableAll()
        XCTAssertEqual(runner.commands.count, ProxyKind.allCases.count)
        XCTAssertNil(service.activeProfileID)
        XCTAssertTrue(runner.commands.allSatisfy { $0.last == "off" })
    }

    func testAddRejectsInvalid() {
        let service = ProxyService(store: InMemoryProxyProfileStore(), runner: RecordingRunner())
        service.add(ProxyProfile(name: "", kind: .http, host: "", port: 0))
        XCTAssertTrue(service.profiles.isEmpty)
        XCTAssertFalse(service.statusMessage.isEmpty)
    }
}

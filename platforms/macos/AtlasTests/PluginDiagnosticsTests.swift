import XCTest
@testable import Atlas

@MainActor
final class PluginDiagnosticsTests: XCTestCase {
    func testLeavingDeveloperModeStopsUnsignedMCP() {
        let runtime = RecordingPluginPlatformRuntime()
        let settings = DeveloperModeSettings(runtime: runtime, enabled: true)

        settings.enabled = false

        XCTAssertEqual(runtime.stoppedTrustTier, "developer-mode")
    }

    func testRecoveryControlsRouteToRuntime() {
        let runtime = RecordingPluginPlatformRuntime()
        let service = PluginPlatformService(runtime: runtime)

        service.restart(pluginID: "dev.example.plugin")
        service.resetCommandBreaker(pluginID: "dev.example.plugin", commandID: "main")
        service.rollback(pluginID: "dev.example.plugin")
        service.clearData(pluginID: "dev.example.plugin")

        XCTAssertEqual(runtime.operations, [
            "restart:dev.example.plugin",
            "reset:dev.example.plugin:main",
            "rollback:dev.example.plugin:false",
            "clear:dev.example.plugin",
        ])
    }
}

private final class RecordingPluginPlatformRuntime: PluginPlatformRuntime, @unchecked Sendable {
    var stoppedTrustTier: String?
    var operations: [String] = []

    func start(callback: any PluginPlatformCallback) throws {}
    func stage(package: Data) throws -> PluginStageResult { throw TestError.unsupported }
    func apply(stageID: String, grants: [PluginCapabilityGrant]) throws {}
    func statuses() throws -> [PluginStatusRecord] { [] }
    func diagnostics(pluginID: String) throws -> PluginDiagnosticRecord { throw TestError.unsupported }
    func startCommand(pluginID: String, commandID: String, argumentsJSON: String) throws -> String { "instance" }
    func sendEvent(pluginID: String, instanceID: String, eventJSON: String) throws {}
    func cancel(pluginID: String, instanceID: String) throws {}
    func respond(requestID: String, responseJSON: String) throws {}
    func stop(pluginID: String) throws { operations.append("stop:\(pluginID)") }
    func restart(pluginID: String) throws { operations.append("restart:\(pluginID)") }

    func resetCommandBreaker(pluginID: String, commandID: String) throws {
        operations.append("reset:\(pluginID):\(commandID)")
    }

    func replaceGrants(pluginID: String, grants: [PluginCapabilityGrant]) throws {
        operations.append("grants:\(pluginID):\(grants.count)")
    }

    func rollback(pluginID: String, clearData: Bool) throws {
        operations.append("rollback:\(pluginID):\(clearData)")
    }

    func clearData(pluginID: String) throws { operations.append("clear:\(pluginID)") }
    func uninstall(pluginID: String) throws { operations.append("uninstall:\(pluginID)") }
    func developerModeEnabled() throws -> Bool { true }

    func setDeveloperMode(enabled: Bool) throws {
        if !enabled { stoppedTrustTier = "developer-mode" }
    }

    func saveDeveloperGrant(
        pluginID: String,
        selectedPaths: [String],
        allowDirectNetwork: Bool,
        approvedCommandsJSON: String
    ) throws {}

    func revokeDeveloperGrant(pluginID: String) throws -> Bool { true }

    enum TestError: Error { case unsupported }
}

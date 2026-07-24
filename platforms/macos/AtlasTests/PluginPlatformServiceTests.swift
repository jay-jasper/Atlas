import XCTest
@testable import Atlas

@MainActor
final class PluginPlatformServiceTests: XCTestCase {
    func testPatchUpdatesOnlyOwningSession() throws {
        let runtime = FakePluginPlatformRuntime()
        let service = PluginPlatformService(runtime: runtime)
        service.receive(event(
            kind: .uiOpen,
            pluginID: "dev.example.one",
            instanceID: "instance-a",
            sessionID: "session-a",
            payload: #"{"title":"Example","root":{"kind":"text","id":"root","value":"old"}}"#
        ))
        service.receive(event(
            kind: .uiPatch,
            pluginID: "dev.example.one",
            instanceID: "instance-a",
            sessionID: "session-a",
            payload: #"{"kind":"set-text","id":"root","value":"new"}"#
        ))
        service.receive(event(
            kind: .uiPatch,
            pluginID: "dev.example.other",
            instanceID: "instance-b",
            sessionID: "session-a",
            payload: #"{"kind":"set-text","id":"root","value":"wrong"}"#
        ))

        XCTAssertEqual(service.sessions["session-a"]?.root.value, .string("new"))
        XCTAssertEqual(service.sessions["session-a"]?.revision, 1)
        XCTAssertNil(service.sessions["session-b"])
    }

    func testConsentCanDenySubset() {
        let service = PluginPlatformService(runtime: FakePluginPlatformRuntime())
        service.receive(event(
            kind: .consentRequired,
            pluginID: "dev.example.one",
            requestID: "stage-1",
            payload: """
            {
              "stageId":"stage-1","pluginId":"dev.example.one","name":"One",
              "version":"1.0.0","publisher":"Example","packageRoot":"abc",
              "requestedCapabilities":["storage.kv","clipboard.read"]
            }
            """
        ))
        service.setCapability("clipboard.read", enabled: false)

        XCTAssertEqual(service.pendingConsent?.selected, Set(["storage.kv"]))
        XCTAssertEqual(service.pendingConsent?.grants.map(\.capability), ["storage.kv"])
    }

    func testUIEventIsRoutedWithOwningPluginAndInstance() {
        let runtime = FakePluginPlatformRuntime()
        let service = PluginPlatformService(runtime: runtime)
        service.receive(event(
            kind: .uiOpen,
            pluginID: "dev.example.one",
            instanceID: "instance-a",
            sessionID: "session-a",
            payload: #"{"title":"Example","root":{"kind":"button","id":"run","label":"Run","action":"run"}}"#
        ))

        service.send(.action(id: "run", action: "run"), sessionID: "session-a")

        XCTAssertEqual(runtime.lastEventPluginID, "dev.example.one")
        XCTAssertEqual(runtime.lastEventInstanceID, "instance-a")
        XCTAssertTrue(runtime.lastEventJSON?.contains("action-invoked") == true)
    }

    func testSuccessfulCommandClearsPreviousError() {
        let service = PluginPlatformService(runtime: FakePluginPlatformRuntime())
        service.receive(event(
            kind: .error,
            pluginID: "dev.example.one",
            payload: #"{"message":"old failure"}"#
        ))

        service.startCommand(pluginID: "dev.example.one", commandID: "main")

        XCTAssertNil(service.lastError)
    }

    private func event(
        kind: PluginHostEventKind,
        pluginID: String,
        instanceID: String? = nil,
        sessionID: String? = nil,
        requestID: String? = nil,
        payload: String
    ) -> PluginHostEvent {
        PluginHostEvent(
            kind: kind,
            pluginId: pluginID,
            commandId: "main",
            instanceId: instanceID,
            sessionId: sessionID,
            requestId: requestID,
            payloadJson: payload
        )
    }
}

private final class FakePluginPlatformRuntime: PluginPlatformRuntime, @unchecked Sendable {
    var callback: (any PluginPlatformCallback)?
    var lastEventPluginID: String?
    var lastEventInstanceID: String?
    var lastEventJSON: String?

    func start(callback: any PluginPlatformCallback) throws { self.callback = callback }
    func stage(package: Data) throws -> PluginStageResult { throw TestError.unsupported }
    func apply(stageID: String, grants: [PluginCapabilityGrant]) throws {}
    func statuses() throws -> [PluginStatusRecord] { [] }
    func diagnostics(pluginID: String) throws -> PluginDiagnosticRecord { throw TestError.unsupported }
    func startCommand(pluginID: String, commandID: String, argumentsJSON: String) throws -> String { "instance" }

    func sendEvent(pluginID: String, instanceID: String, eventJSON: String) throws {
        lastEventPluginID = pluginID
        lastEventInstanceID = instanceID
        lastEventJSON = eventJSON
    }

    func cancel(pluginID: String, instanceID: String) throws {}
    func respond(requestID: String, responseJSON: String) throws {}
    func stop(pluginID: String) throws {}
    func restart(pluginID: String) throws {}
    func resetCommandBreaker(pluginID: String, commandID: String) throws {}
    func replaceGrants(pluginID: String, grants: [PluginCapabilityGrant]) throws {}
    func rollback(pluginID: String, clearData: Bool) throws {}
    func clearData(pluginID: String) throws {}
    func uninstall(pluginID: String) throws {}
    func developerModeEnabled() throws -> Bool { false }
    func setDeveloperMode(enabled: Bool) throws {}
    func saveDeveloperGrant(
        pluginID: String,
        selectedPaths: [String],
        allowDirectNetwork: Bool,
        approvedCommandsJSON: String
    ) throws {}
    func revokeDeveloperGrant(pluginID: String) throws -> Bool { false }

    enum TestError: Error { case unsupported }
}

import Foundation

protocol PluginPlatformRuntime: Sendable {
    func start(callback: any PluginPlatformCallback) throws
    func stage(package: Data) throws -> PluginStageResult
    func apply(stageID: String, grants: [PluginCapabilityGrant]) throws
    func statuses() throws -> [PluginStatusRecord]
    func diagnostics(pluginID: String) throws -> PluginDiagnosticRecord
    func startCommand(pluginID: String, commandID: String, argumentsJSON: String) throws -> String
    func sendEvent(pluginID: String, instanceID: String, eventJSON: String) throws
    func cancel(pluginID: String, instanceID: String) throws
    func respond(requestID: String, responseJSON: String) throws
    func stop(pluginID: String) throws
    func restart(pluginID: String) throws
    func resetCommandBreaker(pluginID: String, commandID: String) throws
    func replaceGrants(pluginID: String, grants: [PluginCapabilityGrant]) throws
    func rollback(pluginID: String, clearData: Bool) throws
    func clearData(pluginID: String) throws
    func uninstall(pluginID: String) throws
    func developerModeEnabled() throws -> Bool
    func setDeveloperMode(enabled: Bool) throws
    func saveDeveloperGrant(
        pluginID: String,
        selectedPaths: [String],
        allowDirectNetwork: Bool,
        approvedCommandsJSON: String
    ) throws
    func revokeDeveloperGrant(pluginID: String) throws -> Bool
}

struct LivePluginPlatformRuntime: PluginPlatformRuntime {
    func start(callback: any PluginPlatformCallback) throws {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Atlas/Plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Atlas.initializePluginStorage(
            rootPath: root.path,
            contentKey: PluginContentKeyStore().loadOrCreate()
        )
        try Atlas.pluginPlatformStart(callback: callback)
    }

    func stage(package: Data) throws -> PluginStageResult {
        try Atlas.pluginStagePackage(packageBytes: Array(package))
    }

    func apply(stageID: String, grants: [PluginCapabilityGrant]) throws {
        try Atlas.pluginApplyGrants(stageId: stageID, grants: grants)
    }

    func statuses() throws -> [PluginStatusRecord] {
        try Atlas.pluginPlatformStatuses()
    }

    func diagnostics(pluginID: String) throws -> PluginDiagnosticRecord {
        try Atlas.pluginExportDiagnostics(pluginId: pluginID)
    }

    func startCommand(pluginID: String, commandID: String, argumentsJSON: String) throws -> String {
        try Atlas.pluginStartCommand(
            pluginId: pluginID,
            commandId: commandID,
            argumentsJson: argumentsJSON
        )
    }

    func sendEvent(pluginID: String, instanceID: String, eventJSON: String) throws {
        try Atlas.pluginSendUiEvent(
            pluginId: pluginID,
            instanceId: instanceID,
            eventJson: eventJSON
        )
    }

    func cancel(pluginID: String, instanceID: String) throws {
        try Atlas.pluginCancelCommand(pluginId: pluginID, instanceId: instanceID)
    }

    func respond(requestID: String, responseJSON: String) throws {
        try Atlas.pluginRespondToHostRequest(requestId: requestID, responseJson: responseJSON)
    }

    func stop(pluginID: String) throws {
        try Atlas.pluginStop(pluginId: pluginID)
    }

    func restart(pluginID: String) throws {
        try Atlas.pluginRestart(pluginId: pluginID)
    }

    func resetCommandBreaker(pluginID: String, commandID: String) throws {
        try Atlas.pluginResetCommandBreaker(pluginId: pluginID, commandId: commandID)
    }

    func replaceGrants(pluginID: String, grants: [PluginCapabilityGrant]) throws {
        try Atlas.pluginReplaceGrants(pluginId: pluginID, grants: grants)
    }

    func rollback(pluginID: String, clearData: Bool) throws {
        try Atlas.pluginRollback(pluginId: pluginID, clearIncompatibleData: clearData)
    }

    func clearData(pluginID: String) throws {
        try Atlas.pluginClearData(pluginId: pluginID)
    }

    func uninstall(pluginID: String) throws {
        try Atlas.pluginPlatformUninstall(pluginId: pluginID)
    }

    func developerModeEnabled() throws -> Bool {
        try Atlas.pluginDeveloperModeEnabled()
    }

    func setDeveloperMode(enabled: Bool) throws {
        try Atlas.pluginSetDeveloperMode(enabled: enabled)
    }

    func saveDeveloperGrant(
        pluginID: String,
        selectedPaths: [String],
        allowDirectNetwork: Bool,
        approvedCommandsJSON: String
    ) throws {
        try Atlas.pluginSaveDeveloperGrant(
            pluginId: pluginID,
            selectedPaths: selectedPaths,
            allowDirectNetwork: allowDirectNetwork,
            approvedCommandsJson: approvedCommandsJSON
        )
    }

    func revokeDeveloperGrant(pluginID: String) throws -> Bool {
        try Atlas.pluginRevokeDeveloperGrant(pluginId: pluginID)
    }
}

struct PluginSessionModel: Equatable, Identifiable {
    let id: String
    let pluginID: String
    let commandID: String
    let instanceID: String
    var title: String
    var root: DynamicPluginNode
    var revision: UInt64 = 0
}

struct PluginConsentRequest: Equatable, Identifiable {
    let stageID: String
    let pluginID: String
    let name: String
    let version: String
    let publisher: String
    let packageRoot: String
    let requested: [String]
    var selected: Set<String>

    var id: String { stageID }
    var grants: [PluginCapabilityGrant] {
        selected.sorted().map { capability in
            let pieces = capability.split(separator: ":", maxSplits: 1).map(String.init)
            return PluginCapabilityGrant(
                capability: pieces[0],
                target: pieces.count == 2 ? pieces[1] : nil
            )
        }
    }
}

private struct PluginOpenPayload: Decodable {
    let title: String
    let root: DynamicPluginNode
}

private struct PluginConsentPayload: Decodable {
    let stageId: String
    let pluginId: String
    let name: String
    let version: String
    let publisher: String
    let packageRoot: String
    let requestedCapabilities: [String]
}

private final class PluginPlatformCallbackBridge: PluginPlatformCallback, @unchecked Sendable {
    let handler: @Sendable (PluginHostEvent) -> Void

    init(handler: @escaping @Sendable (PluginHostEvent) -> Void) {
        self.handler = handler
    }

    func onPluginEvent(event: PluginHostEvent) {
        handler(event)
    }
}

@MainActor
final class PluginPlatformService: ObservableObject {
    @Published private(set) var sessions: [String: PluginSessionModel] = [:]
    @Published private(set) var pendingConsent: PluginConsentRequest?
    @Published private(set) var statuses: [PluginStatusRecord] = []
    @Published private(set) var developerModeEnabled = false
    @Published private(set) var lastError: String?

    private let runtime: any PluginPlatformRuntime
    private let capabilityRouter: PluginCapabilityRouter
    private var callback: PluginPlatformCallbackBridge?

    init(
        runtime: any PluginPlatformRuntime = LivePluginPlatformRuntime(),
        capabilityRouter: PluginCapabilityRouter? = nil,
        startImmediately: Bool = true
    ) {
        self.runtime = runtime
        self.capabilityRouter = capabilityRouter ?? PluginCapabilityRouter(adapters: [
            PluginFeedbackAdapter(),
            PluginPreferencesAdapter(),
            PluginFileAdapter(),
            PluginClipboardAdapter(),
            PluginNotificationAdapter(),
            PluginApplicationAdapter(),
        ])
        if startImmediately {
            start()
        }
    }

    func start() {
        guard callback == nil else { return }
        let callback = PluginPlatformCallbackBridge { [weak self] event in
            Task { @MainActor in self?.receive(event) }
        }
        self.callback = callback
        do {
            try runtime.start(callback: callback)
            developerModeEnabled = try runtime.developerModeEnabled()
            refreshStatuses()
        } catch {
            self.callback = nil
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func stage(packageURL: URL) -> Bool {
        do {
            let result = try runtime.stage(package: Data(contentsOf: packageURL, options: [.mappedIfSafe]))
            setConsent(result)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func applyPendingConsent() {
        guard let pendingConsent else { return }
        do {
            try runtime.apply(stageID: pendingConsent.stageID, grants: pendingConsent.grants)
            self.pendingConsent = nil
            refreshStatuses()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func denyPendingConsent() {
        pendingConsent = nil
    }

    func setCapability(_ capability: String, enabled: Bool) {
        guard var pendingConsent else { return }
        if enabled {
            pendingConsent.selected.insert(capability)
        } else {
            pendingConsent.selected.remove(capability)
        }
        self.pendingConsent = pendingConsent
    }

    func startCommand(pluginID: String, commandID: String, arguments: [String] = []) {
        lastError = nil
        do {
            let data = try JSONEncoder().encode(arguments)
            _ = try runtime.startCommand(
                pluginID: pluginID,
                commandID: commandID,
                argumentsJSON: String(decoding: data, as: UTF8.self)
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func send(_ event: DynamicPluginUIEvent, sessionID: String) {
        guard let session = sessions[sessionID] else { return }
        do {
            try runtime.sendEvent(
                pluginID: session.pluginID,
                instanceID: session.instanceID,
                eventJSON: event.json
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func cancel(sessionID: String) {
        guard let session = sessions[sessionID] else { return }
        do {
            try runtime.cancel(pluginID: session.pluginID, instanceID: session.instanceID)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func uninstall(pluginID: String) {
        do {
            try runtime.uninstall(pluginID: pluginID)
            sessions = sessions.filter { $0.value.pluginID != pluginID }
            refreshStatuses()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop(pluginID: String) {
        performRecovery { try runtime.stop(pluginID: pluginID) }
    }

    func restart(pluginID: String) {
        performRecovery { try runtime.restart(pluginID: pluginID) }
    }

    func resetCommandBreaker(pluginID: String, commandID: String) {
        performRecovery {
            try runtime.resetCommandBreaker(pluginID: pluginID, commandID: commandID)
        }
    }

    func replaceGrants(pluginID: String, grants: [PluginCapabilityGrant]) {
        performRecovery {
            try runtime.replaceGrants(pluginID: pluginID, grants: grants)
        }
    }

    func rollback(pluginID: String, clearData: Bool = false) {
        performRecovery {
            try runtime.rollback(pluginID: pluginID, clearData: clearData)
        }
    }

    func clearData(pluginID: String) {
        performRecovery { try runtime.clearData(pluginID: pluginID) }
    }

    func diagnostics(pluginID: String) -> PluginDiagnosticRecord? {
        do {
            return try runtime.diagnostics(pluginID: pluginID)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func setDeveloperMode(enabled: Bool) {
        do {
            try runtime.setDeveloperMode(enabled: enabled)
            developerModeEnabled = enabled
            refreshStatuses()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshStatuses() {
        do {
            statuses = try runtime.statuses().sorted { $0.pluginId < $1.pluginId }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func receive(_ event: PluginHostEvent) {
        do {
            switch event.kind {
            case .consentRequired:
                let payload = try decode(PluginConsentPayload.self, event.payloadJson)
                pendingConsent = PluginConsentRequest(
                    stageID: payload.stageId,
                    pluginID: payload.pluginId,
                    name: payload.name,
                    version: payload.version,
                    publisher: payload.publisher,
                    packageRoot: payload.packageRoot,
                    requested: payload.requestedCapabilities,
                    selected: Set(payload.requestedCapabilities)
                )
            case .statusChanged:
                refreshStatuses()
            case .uiOpen:
                guard let sessionID = event.sessionId, let instanceID = event.instanceId else { return }
                let payload = try decode(PluginOpenPayload.self, event.payloadJson)
                sessions[sessionID] = PluginSessionModel(
                    id: sessionID,
                    pluginID: event.pluginId,
                    commandID: event.commandId ?? "",
                    instanceID: instanceID,
                    title: payload.title,
                    root: payload.root
                )
            case .uiPatch:
                guard let sessionID = event.sessionId,
                      var session = sessions[sessionID],
                      session.pluginID == event.pluginId,
                      session.instanceID == event.instanceId
                else { return }
                try session.root.apply(decode(DynamicPluginPatch.self, event.payloadJson))
                session.revision += 1
                sessions[sessionID] = session
            case .uiClose:
                guard let sessionID = event.sessionId,
                      sessions[sessionID]?.pluginID == event.pluginId
                else { return }
                sessions.removeValue(forKey: sessionID)
            case .hostRequest:
                guard let requestID = event.requestId else { return }
                let request = try decode(PluginHostRequestPayload.self, event.payloadJson)
                Task {
                    let response = await capabilityRouter.perform(
                        pluginID: event.pluginId,
                        request: request
                    )
                    do {
                        try runtime.respond(requestID: requestID, responseJSON: response)
                    } catch {
                        lastError = error.localizedDescription
                    }
                }
            case .diagnostic:
                break
            case .error:
                lastError = event.payloadJson
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func setConsent(_ result: PluginStageResult) {
        pendingConsent = PluginConsentRequest(
            stageID: result.stageId,
            pluginID: result.pluginId,
            name: result.name,
            version: result.version,
            publisher: result.publisher,
            packageRoot: result.packageRoot,
            requested: result.requestedCapabilities,
            selected: Set(result.requestedCapabilities)
        )
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func performRecovery(_ operation: () throws -> Void) {
        do {
            try operation()
            refreshStatuses()
        } catch {
            lastError = error.localizedDescription
        }
    }
}

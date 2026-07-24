import AppKit
import Foundation
import SwiftUI

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

struct PluginCatalogLocalization: Decodable, Equatable {
    let title: String?
    let description: String?
    let aliases: [String]

    private enum CodingKeys: String, CodingKey {
        case title, description, aliases
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        aliases = try values.decodeIfPresent([String].self, forKey: .aliases) ?? []
    }
}

struct PluginCatalogCommand: Decodable, Equatable {
    let id: String
    let title: String
    let description: String
    let aliases: [String]
    let localizations: [String: PluginCatalogLocalization]

    func localized(preferredLanguages: [String]) -> PluginResolvedCommand {
        let localization = localizations.bestMatch(for: preferredLanguages)
        return PluginResolvedCommand(
            id: id,
            title: localization?.title ?? title,
            description: localization?.description ?? description,
            aliases: aliases + localizations.values.flatMap(\.aliases)
        )
    }
}

struct PluginCatalogPayload: Decodable, Equatable {
    let title: String
    let description: String
    let aliases: [String]
    let localizations: [String: PluginCatalogLocalization]
    let commands: [PluginCatalogCommand]

    private enum CodingKeys: String, CodingKey {
        case title, description, aliases, localizations, commands
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        aliases = try values.decodeIfPresent([String].self, forKey: .aliases) ?? []
        localizations =
            try values.decodeIfPresent([String: PluginCatalogLocalization].self, forKey: .localizations) ?? [:]
        commands = try values.decodeIfPresent([PluginCatalogCommand].self, forKey: .commands) ?? []
    }

    func localized(preferredLanguages: [String] = Locale.preferredLanguages) -> PluginResolvedCatalog {
        let localization = localizations.bestMatch(for: preferredLanguages)
        return PluginResolvedCatalog(
            title: localization?.title ?? title,
            description: localization?.description ?? description,
            aliases: aliases + localizations.values.flatMap(\.aliases),
            commands: commands.map { $0.localized(preferredLanguages: preferredLanguages) }
        )
    }
}

struct PluginResolvedCommand: Equatable {
    let id: String
    let title: String
    let description: String
    let aliases: [String]
}

struct PluginResolvedCatalog: Equatable {
    let title: String
    let description: String
    let aliases: [String]
    let commands: [PluginResolvedCommand]
}

extension PluginStatusRecord {
    func resolvedCatalog(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> PluginResolvedCatalog {
        let decoded = try? JSONDecoder().decode(
            PluginCatalogPayload.self,
            from: Data(catalogJson.utf8)
        )
        return decoded?.localized(preferredLanguages: preferredLanguages)
            ?? PluginResolvedCatalog(
                title: pluginId,
                description: "",
                aliases: [],
                commands: []
            )
    }

    func matchesCatalogQuery(
        _ query: String,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        let catalog = resolvedCatalog(preferredLanguages: preferredLanguages)
        return ([catalog.title, catalog.description, pluginId, version] + catalog.aliases)
            .contains { $0.localizedCaseInsensitiveContains(normalized) }
    }
}

private extension Dictionary where Key == String, Value == PluginCatalogLocalization {
    func bestMatch(for preferredLanguages: [String]) -> PluginCatalogLocalization? {
        let normalized = Dictionary(uniqueKeysWithValues: map { key, value in
            (key.replacingOccurrences(of: "_", with: "-").lowercased(), value)
        })
        for language in preferredLanguages {
            let candidate = language.replacingOccurrences(of: "_", with: "-").lowercased()
            if let exact = normalized[candidate] {
                return exact
            }
            let base = candidate.split(separator: "-").first.map(String.init) ?? candidate
            if let baseMatch = normalized[base] {
                return baseMatch
            }
            if let regional = normalized.first(where: { $0.key.hasPrefix("\(base)-") })?.value {
                return regional
            }
        }
        return nil
    }
}

@MainActor
final class PluginCommandProvider: @preconcurrency CommandProviding {
    private unowned let service: PluginPlatformService
    private let preferredLanguages: () -> [String]

    init(
        service: PluginPlatformService,
        preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages }
    ) {
        self.service = service
        self.preferredLanguages = preferredLanguages
    }

    func results(for query: String) -> [PaletteCommand] {
        let preferredLanguages = preferredLanguages()
        let commands = service.statuses.flatMap { status -> [PaletteCommand] in
            let catalog = status.resolvedCatalog(preferredLanguages: preferredLanguages)
            let pluginTitle = catalog.title.nilIfEmpty ?? status.pluginId
            let pluginDescription = catalog.description
            let pluginAliases = catalog.aliases
            let entries = catalog.commands.isEmpty == false
                ? catalog.commands
                : [PluginResolvedCommand(id: "main", title: pluginTitle, description: pluginDescription, aliases: [])]
            return entries.map { command in
                PaletteCommand(
                    id: UUID(),
                    title: command.title,
                    subtitle: command.description.nilIfEmpty ?? pluginDescription.nilIfEmpty ?? pluginTitle,
                    icon: .sfSymbol("puzzlepiece.extension"),
                    keywords: Array(Set(
                        pluginAliases
                            + command.aliases
                            + [status.pluginId, command.id, pluginTitle, "plugin", "插件"]
                    )),
                    action: .execute { [weak service] in
                        service?.startCommand(pluginID: status.pluginId, commandID: command.id)
                    },
                    category: pluginTitle
                )
            }
        }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return commands }
        return commands.filter {
            $0.title.localizedCaseInsensitiveContains(normalizedQuery)
                || ($0.subtitle?.localizedCaseInsensitiveContains(normalizedQuery) == true)
                || $0.keywords.contains { $0.localizedCaseInsensitiveContains(normalizedQuery) }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct PluginSessionWindowView: View {
    @ObservedObject var service: PluginPlatformService
    let sessionID: String

    var body: some View {
        Group {
            if let session = service.sessions[sessionID] {
                DynamicPluginView(node: session.root, pluginID: session.pluginID) {
                    service.send($0, sessionID: session.id)
                }
                .id(session.revision)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}

@MainActor
private final class PluginSessionWindowController: NSWindowController, NSWindowDelegate {
    private weak var service: PluginPlatformService?
    private let sessionID: String

    init(service: PluginPlatformService, sessionID: String, title: String) {
        self.service = service
        self.sessionID = sessionID
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.minSize = NSSize(width: 720, height: 520)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: PluginSessionWindowView(service: service, sessionID: sessionID)
        )
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        service?.sessionWindowDidClose(sessionID: sessionID)
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
    private let presentsSessionWindows: Bool
    private var callback: PluginPlatformCallbackBridge?
    private var sessionWindows: [String: PluginSessionWindowController] = [:]

    init(
        runtime: any PluginPlatformRuntime = LivePluginPlatformRuntime(),
        capabilityRouter: PluginCapabilityRouter? = nil,
        startImmediately: Bool = true,
        presentsSessionWindows: Bool? = nil
    ) {
        self.runtime = runtime
        let runningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.presentsSessionWindows = presentsSessionWindows ?? !runningTests
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

    func startDefaultCommand(pluginID: String) {
        let commandID = statuses
            .first(where: { $0.pluginId == pluginID })
            .flatMap {
                try? JSONDecoder().decode(
                    PluginCatalogPayload.self,
                    from: Data($0.catalogJson.utf8)
                )
            }?
            .commands
            .first?
            .id ?? "main"
        startCommand(pluginID: pluginID, commandID: commandID)
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
            for session in sessions.values where session.pluginID == pluginID {
                closeSessionWindow(sessionID: session.id)
            }
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
                presentSessionWindow(sessionID: sessionID)
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
                closeSessionWindow(sessionID: sessionID)
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

    fileprivate func sessionWindowDidClose(sessionID: String) {
        sessionWindows.removeValue(forKey: sessionID)
        guard let session = sessions.removeValue(forKey: sessionID) else { return }
        do {
            try runtime.cancel(pluginID: session.pluginID, instanceID: session.instanceID)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func presentSessionWindow(sessionID: String) {
        guard presentsSessionWindows, let session = sessions[sessionID] else { return }
        let controller = sessionWindows[sessionID] ?? PluginSessionWindowController(
            service: self,
            sessionID: sessionID,
            title: session.title
        )
        sessionWindows[sessionID] = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func closeSessionWindow(sessionID: String) {
        guard let controller = sessionWindows.removeValue(forKey: sessionID) else { return }
        controller.window?.delegate = nil
        controller.close()
    }
}

import AppKit
import Foundation
import SwiftUI

enum SceneIntent: String, Codable, CaseIterable, Identifiable {
    case focus
    case meeting
    case collection
    case presentation
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus:
            return "Focus"
        case .meeting:
            return "Meeting"
        case .collection:
            return "Collection"
        case .presentation:
            return "Presentation"
        case .custom:
            return "Custom"
        }
    }
}

enum SceneMergePolicy: String, Codable, CaseIterable, Identifiable {
    case replace
    case append
    case explicitDisable = "explicit-disable"

    var id: String { rawValue }
}

enum SceneModuleID: String, Codable, CaseIterable, Identifiable {
    case aiLoadMonitor = "ai-load-monitor"
    case audioHub = "audio-hub"
    case clipboard
    case flowInbox = "flow-inbox"
    case monitoring
    case privacy
    case scratchpad
    case screenshot
    case systemUtilities = "system-utilities"
    case tokenbar
    case windowManager = "window-manager"
    case cameraPreview = "camera-preview"
    case bluetooth = "bluetooth"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aiLoadMonitor:
            return "AI Load"
        case .audioHub:
            return "Audio Hub"
        case .clipboard:
            return "Clipboard"
        case .flowInbox:
            return "Flow Inbox"
        case .monitoring:
            return "Monitoring"
        case .privacy:
            return "Privacy Pulse"
        case .scratchpad:
            return "Scratchpad"
        case .screenshot:
            return "Screenshot"
        case .systemUtilities:
            return "System Utilities"
        case .tokenbar:
            return "TokenBar"
        case .windowManager:
            return "Window Manager"
        case .cameraPreview:
            return "Camera Preview"
        case .bluetooth:
            return "Bluetooth"
        }
    }
}

enum SceneModuleState: String, Codable, CaseIterable, Identifiable {
    case enabled
    case disabled
    case onDemand = "on-demand"

    var id: String { rawValue }
}

enum SceneModuleVisibility: String, Codable, CaseIterable, Identifiable {
    case automatic
    case promoted
    case hidden

    var id: String { rawValue }
}

struct SceneModuleOverride: Codable, Equatable, Identifiable {
    var moduleID: SceneModuleID
    var state: SceneModuleState
    var visibility: SceneModuleVisibility
    var panelOrder: Int?
    var pinnedActions: [String]
    var settings: [String: String]

    var id: SceneModuleID { moduleID }

    init(
        moduleID: SceneModuleID,
        state: SceneModuleState = .enabled,
        visibility: SceneModuleVisibility = .automatic,
        panelOrder: Int? = nil,
        pinnedActions: [String] = [],
        settings: [String: String] = [:]
    ) {
        self.moduleID = moduleID
        self.state = state
        self.visibility = visibility
        self.panelOrder = panelOrder
        self.pinnedActions = pinnedActions
        self.settings = settings
    }
}

enum SceneTriggerType: String, Codable, CaseIterable, Identifiable {
    case manual
    case hotkey
    case schedule
    case appFocus = "app-focus"
    case bluetoothDevice = "bluetooth-device"
    case audioDevice = "audio-device"
    case network
    case display
    case powerState = "power-state"
    case idleState = "idle-state"

    var id: String { rawValue }
}

struct SceneTriggerMatch: Codable, Equatable {
    var primary: String
    var secondary: String
    var values: [String]

    init(primary: String = "", secondary: String = "", values: [String] = []) {
        self.primary = primary
        self.secondary = secondary
        self.values = values
    }
}

struct SceneTrigger: Codable, Equatable, Identifiable {
    var id: UUID
    var type: SceneTriggerType
    var match: SceneTriggerMatch
    var debounce: TimeInterval?
    var cooldown: TimeInterval?
    var enabled: Bool

    init(
        id: UUID = UUID(),
        type: SceneTriggerType,
        match: SceneTriggerMatch = SceneTriggerMatch(),
        debounce: TimeInterval? = nil,
        cooldown: TimeInterval? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.type = type
        self.match = match
        self.debounce = debounce
        self.cooldown = cooldown
        self.enabled = enabled
    }
}

enum SceneActionType: String, Codable, CaseIterable, Identifiable {
    case atlasAction = "atlas-action"
    case systemAction = "system-action"
    case scriptAction = "script-action"
    case aiSkillAction = "ai-skill-action"

    var id: String { rawValue }
}

enum SceneActionFailurePolicy: String, Codable, CaseIterable, Identifiable {
    case `continue`
    case stop
    case rollback
    case notifyOnly = "notify-only"

    var id: String { rawValue }
}

enum SceneActionRetryPolicy: String, Codable, CaseIterable, Identifiable {
    case none
    case retryOnce = "retry-once"
    case retryTwice = "retry-twice"
    case retryThrice = "retry-thrice"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return "No Retry"
        case .retryOnce:
            return "Retry Once"
        case .retryTwice:
            return "Retry Twice"
        case .retryThrice:
            return "Retry Thrice"
        }
    }

    var retryCount: Int {
        switch self {
        case .none:
            return 0
        case .retryOnce:
            return 1
        case .retryTwice:
            return 2
        case .retryThrice:
            return 3
        }
    }

    static func fromLegacyRetryCount(_ retryCount: Int) -> SceneActionRetryPolicy {
        switch retryCount {
        case ..<1:
            return .none
        case 1:
            return .retryOnce
        case 2:
            return .retryTwice
        default:
            return .retryThrice
        }
    }
}

struct SceneAction: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var type: SceneActionType
    var params: [String: String]
    var timeout: TimeInterval
    var retryPolicy: SceneActionRetryPolicy
    var failurePolicy: SceneActionFailurePolicy

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case type
        case params
        case timeout
        case retryPolicy
        case retryCount
        case failurePolicy
    }

    init(
        id: UUID = UUID(),
        title: String,
        type: SceneActionType,
        params: [String: String] = [:],
        timeout: TimeInterval = 10,
        retryPolicy: SceneActionRetryPolicy = .none,
        failurePolicy: SceneActionFailurePolicy = .continue
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.params = params
        self.timeout = timeout
        self.retryPolicy = retryPolicy
        self.failurePolicy = failurePolicy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        type = try container.decode(SceneActionType.self, forKey: .type)
        params = try container.decodeIfPresent([String: String].self, forKey: .params) ?? [:]
        timeout = try container.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? 10
        if let retryPolicy = try container.decodeIfPresent(SceneActionRetryPolicy.self, forKey: .retryPolicy) {
            self.retryPolicy = retryPolicy
        } else {
            let legacyRetryCount = try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0
            self.retryPolicy = .fromLegacyRetryCount(legacyRetryCount)
        }
        failurePolicy = try container.decodeIfPresent(SceneActionFailurePolicy.self, forKey: .failurePolicy) ?? .continue
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(type, forKey: .type)
        try container.encode(params, forKey: .params)
        try container.encode(timeout, forKey: .timeout)
        try container.encode(retryPolicy, forKey: .retryPolicy)
        try container.encode(failurePolicy, forKey: .failurePolicy)
    }
}

struct SceneBehaviorRules: Codable, Equatable {
    var newScreenshotsGoToInbox: Bool
    var preferInboxFavorites: Bool
    var prioritizeRecentContent: Bool
    var promoteCommandPaletteCategory: String

    static let `default` = SceneBehaviorRules(
        newScreenshotsGoToInbox: true,
        preferInboxFavorites: false,
        prioritizeRecentContent: true,
        promoteCommandPaletteCategory: ""
    )
}

struct SceneDefinition: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var icon: String
    var intent: SceneIntent
    var tags: [String]
    var createdBy: String
    var updatedAt: Date
    var extends: UUID?
    var mergePolicy: SceneMergePolicy
    var priority: Int
    var moduleOverrides: [SceneModuleOverride]
    var triggers: [SceneTrigger]
    var onEnter: [SceneAction]
    var onExit: [SceneAction]
    var onFail: [SceneAction]
    var postActivate: [SceneAction]
    var behaviorRules: SceneBehaviorRules
    var isBuiltIn: Bool

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "square.stack.3d.up.fill",
        intent: SceneIntent = .custom,
        tags: [String] = [],
        createdBy: String = "user",
        updatedAt: Date = Date(),
        extends: UUID? = nil,
        mergePolicy: SceneMergePolicy = .replace,
        priority: Int = 0,
        moduleOverrides: [SceneModuleOverride] = [],
        triggers: [SceneTrigger] = [],
        onEnter: [SceneAction] = [],
        onExit: [SceneAction] = [],
        onFail: [SceneAction] = [],
        postActivate: [SceneAction] = [],
        behaviorRules: SceneBehaviorRules = .default,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.intent = intent
        self.tags = tags
        self.createdBy = createdBy
        self.updatedAt = updatedAt
        self.extends = extends
        self.mergePolicy = mergePolicy
        self.priority = priority
        self.moduleOverrides = moduleOverrides
        self.triggers = triggers
        self.onEnter = onEnter
        self.onExit = onExit
        self.onFail = onFail
        self.postActivate = postActivate
        self.behaviorRules = behaviorRules
        self.isBuiltIn = isBuiltIn
    }
}

struct ResolvedScene: Equatable {
    let definition: SceneDefinition
    let moduleOverrides: [SceneModuleOverride]
    let onEnter: [SceneAction]
    let onExit: [SceneAction]
    let onFail: [SceneAction]
    let postActivate: [SceneAction]
    let behaviorRules: SceneBehaviorRules
}

struct ScenePreview {
    enum DryRunStatus: String {
        case ready
        case attention
        case unavailable
    }

    struct ActionPreview: Identifiable {
        let id = UUID()
        let summary: String
        let status: DryRunStatus
        let detail: String
    }

    struct ActionPhase: Identifiable {
        let id = UUID()
        let title: String
        let actions: [ActionPreview]
    }

    let definition: SceneDefinition
    let resolved: ResolvedScene
    let triggerSummaries: [String]
    let actionPhases: [ActionPhase]
    let moduleSnapshots: [SceneModuleCapabilitySnapshot]
}

struct SceneAudioRoute: Equatable {
    var outputDeviceID: UInt32?
    var inputDeviceID: UInt32?
}

struct SceneExecutionRecord: Codable, Equatable, Identifiable {
    enum Status: String, Codable {
        case success
        case failed
        case skipped
    }

    var id: UUID
    var sceneID: UUID?
    var sceneName: String
    var reason: String
    var status: Status
    var detail: String
    var timestamp: Date

    init(
        id: UUID = UUID(),
        sceneID: UUID?,
        sceneName: String,
        reason: String,
        status: Status,
        detail: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.sceneID = sceneID
        self.sceneName = sceneName
        self.reason = reason
        self.status = status
        self.detail = detail
        self.timestamp = timestamp
    }
}

struct ScenePinnedActionItem: Identifiable {
    let id = UUID()
    let moduleID: SceneModuleID
    let rawValue: String
    let title: String
    let isEnabled: Bool
}

private struct SceneDocument: Codable {
    var scenes: [SceneDefinition]
}

struct SceneRuntimeState: Codable {
    var activeSceneID: UUID?
    var lastManualSceneID: UUID?
    var activeSceneReason: String
    var triggerLastFiredAt: [UUID: Date]
    var triggerFirstMatchedAt: [UUID: Date]

    init(
        activeSceneID: UUID?,
        lastManualSceneID: UUID?,
        activeSceneReason: String = "Manual",
        triggerLastFiredAt: [UUID: Date] = [:],
        triggerFirstMatchedAt: [UUID: Date] = [:]
    ) {
        self.activeSceneID = activeSceneID
        self.lastManualSceneID = lastManualSceneID
        self.activeSceneReason = activeSceneReason
        self.triggerLastFiredAt = triggerLastFiredAt
        self.triggerFirstMatchedAt = triggerFirstMatchedAt
    }
}

private struct SceneHistoryDocument: Codable {
    var records: [SceneExecutionRecord]
}

final class SceneStore {
    private let scenesURL: URL
    private let stateURL: URL
    private let historyURL: URL
    private let legacyHistoryURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(rootDirectory: URL = SceneStore.defaultRootDirectory(), fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.scenesURL = rootDirectory.appendingPathComponent("scenes.json")
        self.stateURL = rootDirectory.appendingPathComponent("scene_state.json")
        self.historyURL = rootDirectory.appendingPathComponent("scene_history.log")
        self.legacyHistoryURL = rootDirectory.appendingPathComponent("scene_history.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadScenes() throws -> [SceneDefinition] {
        guard fileManager.fileExists(atPath: scenesURL.path) else {
            let defaults = Self.defaultScenes()
            try saveScenes(defaults)
            return defaults
        }

        let data = try Data(contentsOf: scenesURL)
        let document = try decoder.decode(SceneDocument.self, from: data)
        return SceneStore.mergedWithDefaults(document.scenes)
    }

    func saveScenes(_ scenes: [SceneDefinition]) throws {
        try createRootDirectory()
        let document = SceneDocument(scenes: scenes)
        let data = try encoder.encode(document)
        try data.write(to: scenesURL, options: .atomic)
    }

    func loadRuntimeState() -> SceneRuntimeState {
        guard fileManager.fileExists(atPath: stateURL.path),
              let data = try? Data(contentsOf: stateURL),
              let state = try? decoder.decode(SceneRuntimeState.self, from: data) else {
            return SceneRuntimeState(activeSceneID: Self.defaultScenes().first?.id, lastManualSceneID: nil)
        }
        return state
    }

    func saveRuntimeState(_ state: SceneRuntimeState) throws {
        try createRootDirectory()
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: .atomic)
    }

    func loadHistory() -> [SceneExecutionRecord] {
        let sourceURL: URL
        if fileManager.fileExists(atPath: historyURL.path) {
            sourceURL = historyURL
        } else if fileManager.fileExists(atPath: legacyHistoryURL.path) {
            sourceURL = legacyHistoryURL
        } else {
            return []
        }
        guard let data = try? Data(contentsOf: sourceURL),
              let history = try? decoder.decode(SceneHistoryDocument.self, from: data) else {
            return []
        }
        return history.records
    }

    func appendHistory(_ record: SceneExecutionRecord, maxCount: Int = 100) throws {
        try createRootDirectory()
        var history = loadHistory()
        history.insert(record, at: 0)
        history = Array(history.prefix(maxCount))
        let data = try encoder.encode(SceneHistoryDocument(records: history))
        try data.write(to: historyURL, options: .atomic)
    }

    private func createRootDirectory() throws {
        try fileManager.createDirectory(at: scenesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private static func defaultRootDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Atlas", isDirectory: true)
            .appendingPathComponent("Scene System", isDirectory: true)
    }

    private static func mergedWithDefaults(_ scenes: [SceneDefinition]) -> [SceneDefinition] {
        let defaults = defaultScenes()
        var output: [SceneDefinition] = []
        let existingByID = Dictionary(uniqueKeysWithValues: scenes.map { ($0.id, $0) })

        for builtIn in defaults {
            output.append(existingByID[builtIn.id] ?? builtIn)
        }

        for scene in scenes where defaults.contains(where: { $0.id == scene.id }) == false {
            output.append(scene)
        }

        return output
    }

    static func defaultScenes() -> [SceneDefinition] {
        let focusID = UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF")!
        let meetingID = UUID(uuidString: "11112233-4455-6677-8899-AABBCCDDEEFF")!
        let collectionID = UUID(uuidString: "22112233-4455-6677-8899-AABBCCDDEEFF")!
        let presentationID = UUID(uuidString: "33112233-4455-6677-8899-AABBCCDDEEFF")!

        let focus = SceneDefinition(
            id: focusID,
            name: "Focus",
            icon: "moon.stars",
            intent: .focus,
            tags: ["deep work", "writing"],
            createdBy: "Atlas",
            priority: 10,
            moduleOverrides: [
                SceneModuleOverride(moduleID: .scratchpad, visibility: .promoted, panelOrder: 0),
                SceneModuleOverride(moduleID: .flowInbox, visibility: .promoted, panelOrder: 1),
                SceneModuleOverride(moduleID: .monitoring, visibility: .hidden),
            ],
            behaviorRules: SceneBehaviorRules(
                newScreenshotsGoToInbox: true,
                preferInboxFavorites: true,
                prioritizeRecentContent: true,
                promoteCommandPaletteCategory: "Scratchpad"
            ),
            isBuiltIn: true
        )

        let meeting = SceneDefinition(
            id: meetingID,
            name: "Meeting",
            icon: "video",
            intent: .meeting,
            tags: ["camera", "share"],
            createdBy: "Atlas",
            priority: 40,
            moduleOverrides: [
                SceneModuleOverride(moduleID: .audioHub, visibility: .promoted, panelOrder: 0),
                SceneModuleOverride(moduleID: .cameraPreview, visibility: .promoted, panelOrder: 1),
                SceneModuleOverride(moduleID: .flowInbox, visibility: .promoted, panelOrder: 2),
            ],
            triggers: [
                SceneTrigger(type: .appFocus, match: SceneTriggerMatch(primary: "us.zoom.xos", secondary: "zoom.us", values: [])),
            ],
            onEnter: [
                SceneAction(title: "Open Camera Preview", type: .atlasAction, params: ["name": "open-hand-mirror"]),
            ],
            behaviorRules: SceneBehaviorRules(
                newScreenshotsGoToInbox: true,
                preferInboxFavorites: false,
                prioritizeRecentContent: true,
                promoteCommandPaletteCategory: "System Utilities"
            ),
            isBuiltIn: true
        )

        let collection = SceneDefinition(
            id: collectionID,
            name: "Collection",
            icon: "tray.full",
            intent: .collection,
            tags: ["capture", "research"],
            createdBy: "Atlas",
            priority: 20,
            moduleOverrides: [
                SceneModuleOverride(moduleID: .flowInbox, visibility: .promoted, panelOrder: 0),
                SceneModuleOverride(moduleID: .clipboard, visibility: .promoted, panelOrder: 1),
                SceneModuleOverride(moduleID: .screenshot, visibility: .promoted, panelOrder: 2),
            ],
            behaviorRules: SceneBehaviorRules(
                newScreenshotsGoToInbox: true,
                preferInboxFavorites: false,
                prioritizeRecentContent: true,
                promoteCommandPaletteCategory: "Atlas"
            ),
            isBuiltIn: true
        )

        let presentation = SceneDefinition(
            id: presentationID,
            name: "Presentation",
            icon: "person.crop.rectangle.stack",
            intent: .presentation,
            tags: ["external display", "speaker"],
            createdBy: "Atlas",
            priority: 30,
            moduleOverrides: [
                SceneModuleOverride(moduleID: .systemUtilities, visibility: .promoted, panelOrder: 0),
                SceneModuleOverride(moduleID: .audioHub, visibility: .promoted, panelOrder: 1),
            ],
            onEnter: [
                SceneAction(title: "Presentation Mode", type: .atlasAction, params: ["name": "toggle-presentation-mode"]),
            ],
            behaviorRules: SceneBehaviorRules(
                newScreenshotsGoToInbox: true,
                preferInboxFavorites: false,
                prioritizeRecentContent: false,
                promoteCommandPaletteCategory: "System Utilities"
            ),
            isBuiltIn: true
        )

        return [focus, meeting, collection, presentation]
    }
}

enum SceneResolver {
    static func resolve(sceneID: UUID, scenes: [SceneDefinition]) -> ResolvedScene? {
        let sceneByID = Dictionary(uniqueKeysWithValues: scenes.map { ($0.id, $0) })
        guard let scene = sceneByID[sceneID] else {
            return nil
        }

        let inherited = scene.extends.flatMap { resolve(sceneID: $0, scenes: scenes) }
        let moduleOverrides = mergeModuleOverrides(
            base: inherited?.moduleOverrides ?? [],
            next: scene.moduleOverrides,
            policy: scene.mergePolicy
        )

        return ResolvedScene(
            definition: scene,
            moduleOverrides: moduleOverrides,
            onEnter: mergeActions(base: inherited?.onEnter ?? [], next: scene.onEnter, policy: scene.mergePolicy),
            onExit: mergeActions(base: inherited?.onExit ?? [], next: scene.onExit, policy: scene.mergePolicy),
            onFail: mergeActions(base: inherited?.onFail ?? [], next: scene.onFail, policy: scene.mergePolicy),
            postActivate: mergeActions(base: inherited?.postActivate ?? [], next: scene.postActivate, policy: scene.mergePolicy),
            behaviorRules: mergeBehaviorRules(base: inherited?.behaviorRules, next: scene.behaviorRules, policy: scene.mergePolicy)
        )
    }

    private static func mergeActions(base: [SceneAction], next: [SceneAction], policy: SceneMergePolicy) -> [SceneAction] {
        switch policy {
        case .replace, .explicitDisable:
            return next.isEmpty ? base : next
        case .append:
            return base + next
        }
    }

    private static func mergeModuleOverrides(
        base: [SceneModuleOverride],
        next: [SceneModuleOverride],
        policy: SceneMergePolicy
    ) -> [SceneModuleOverride] {
        switch policy {
        case .replace:
            return next.isEmpty ? base : next
        case .append, .explicitDisable:
            var merged = Dictionary(uniqueKeysWithValues: base.map { ($0.moduleID, $0) })
            for override in next {
                merged[override.moduleID] = override
            }
            return SceneModuleID.allCases.compactMap { merged[$0] }
        }
    }

    private static func mergeBehaviorRules(
        base: SceneBehaviorRules?,
        next: SceneBehaviorRules,
        policy: SceneMergePolicy
    ) -> SceneBehaviorRules {
        guard let base else {
            return next
        }
        guard policy == .append else {
            return next
        }
        let defaults = SceneBehaviorRules.default
        return SceneBehaviorRules(
            newScreenshotsGoToInbox: next.newScreenshotsGoToInbox == defaults.newScreenshotsGoToInbox
                ? base.newScreenshotsGoToInbox
                : next.newScreenshotsGoToInbox,
            preferInboxFavorites: next.preferInboxFavorites == defaults.preferInboxFavorites
                ? base.preferInboxFavorites
                : next.preferInboxFavorites,
            prioritizeRecentContent: next.prioritizeRecentContent == defaults.prioritizeRecentContent
                ? base.prioritizeRecentContent
                : next.prioritizeRecentContent,
            promoteCommandPaletteCategory: next.promoteCommandPaletteCategory.isEmpty
                ? base.promoteCommandPaletteCategory
                : next.promoteCommandPaletteCategory
        )
    }
}

struct SceneRuntimeContext {
    var toggleKeepAwake: (() -> Void)?
    var togglePresentationMode: (() -> Void)?
    var openHandMirror: (() -> Void)?
    var refreshDisplays: (() -> Void)?
    var applyAudioPreset: ((String) -> Void)?
    var runAutomation: ((CustomAutomationCommand) async -> AutomationProcessResult)?
    var runSkillNamed: ((String) async -> Bool)?
    var saveTextToScratchpad: ((String, String) -> UUID?)?
    var deleteScratchpadNote: ((UUID) -> Void)?
    var registerSceneHotkey: ((Int, UInt, @escaping () -> Void) -> Void)?
    var unregisterSceneHotkey: ((Int, UInt) -> Void)?
    var currentAudioDeviceNames: (() -> [String])?
    var currentBluetoothDeviceNames: (() -> [String])?
    var currentNetworkTriggerTokens: (() -> [String])?
    var currentDisplayTriggerTokens: (() -> [String])?
    var currentPowerStateTriggerTokens: (() -> [String])?
    var currentIdleSeconds: (() -> TimeInterval)?
    var currentKeepAwakeActive: (() -> Bool)?
    var currentPresentationModeActive: (() -> Bool)?
    var currentAudioRoute: (() -> SceneAudioRoute)?
    var restoreAudioRoute: ((SceneAudioRoute) -> Void)?
    var availableAudioPresetTitles: (() -> [String])?
    var availableSkillTitles: (() -> [String])?
    var currentCameraPermissionState: (() -> CameraPermissionState)?
    var moduleSnapshots: (() -> [SceneModuleCapabilitySnapshot])?
}

struct SceneModuleCapabilitySnapshot: Identifiable, Equatable {
    let moduleID: SceneModuleID
    let isAvailable: Bool
    let stateSummary: String
    let configurableSettings: [String]
    let supportedActions: [String]

    var id: SceneModuleID { moduleID }
}

protocol SceneControllableModule {
    var moduleID: SceneModuleID { get }
    var isSceneControllable: Bool { get }
    var configurableSettings: [String] { get }
    var supportedActions: [String] { get }
    func capabilitySnapshot() -> SceneModuleCapabilitySnapshot
}

struct AnySceneControllableModule: SceneControllableModule {
    let moduleID: SceneModuleID
    let isSceneControllable: Bool
    let configurableSettings: [String]
    let supportedActions: [String]
    private let snapshotBuilder: () -> SceneModuleCapabilitySnapshot

    init<T: SceneControllableModule>(_ base: T) {
        self.moduleID = base.moduleID
        self.isSceneControllable = base.isSceneControllable
        self.configurableSettings = base.configurableSettings
        self.supportedActions = base.supportedActions
        self.snapshotBuilder = base.capabilitySnapshot
    }

    func capabilitySnapshot() -> SceneModuleCapabilitySnapshot {
        snapshotBuilder()
    }
}

private struct SceneMatchCandidate {
    let scene: SceneDefinition
    let trigger: SceneTrigger
    let specificity: Int
    let reasonDetail: String
}

private struct SceneActivationEvent {
    let sceneID: UUID
    let timestamp: Date
}

final class SceneCoordinator: ObservableObject {
    @Published private(set) var scenes: [SceneDefinition] = []
    @Published private(set) var activeSceneID: UUID?
    @Published private(set) var lastManualSceneID: UUID?
    @Published private(set) var resolvedScene: ResolvedScene?
    @Published private(set) var history: [SceneExecutionRecord] = []
    @Published private(set) var currentActivationReason: String = "Manual"

    private let store: SceneStore
    private var runtimeContext = SceneRuntimeContext()
    private var appObserver: NSObjectProtocol?
    private var displayObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var scheduleTimer: Timer?
    private var registeredHotkeys: [(keyCode: Int, modifiers: UInt)] = []
    private var consecutiveFailureCount = 0
    private var isSafeModeEnabled = false
    private var sessionManualOverrides = Set<String>()
    private var triggerFirstMatchedAt: [UUID: Date] = [:]
    private var triggerLastFiredAt: [UUID: Date] = [:]
    private var recentAutomaticActivations: [SceneActivationEvent] = []
    private var isRunning = false

    init(store: SceneStore = SceneStore()) {
        self.store = store
    }

    func configure(runtimeContext: SceneRuntimeContext) {
        self.runtimeContext = runtimeContext
    }

    func start() {
        guard isRunning == false else { return }
        do {
            scenes = try store.loadScenes()
        } catch {
            scenes = SceneStore.defaultScenes()
        }

        let state = store.loadRuntimeState()
        activeSceneID = state.activeSceneID ?? scenes.first?.id
        lastManualSceneID = state.lastManualSceneID
        currentActivationReason = state.activeSceneReason
        triggerLastFiredAt = state.triggerLastFiredAt
        triggerFirstMatchedAt = state.triggerFirstMatchedAt
        history = store.loadHistory()
        if let activeSceneID {
            resolvedScene = SceneResolver.resolve(sceneID: activeSceneID, scenes: scenes)
        }
        startObservers()
        registerHotkeyTriggers()
        startScheduleTimer()
        evaluateAutomaticTriggers(reason: "Scene coordinator started")
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        if let appObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appObserver)
            self.appObserver = nil
        }
        if let displayObserver {
            NotificationCenter.default.removeObserver(displayObserver)
            self.displayObserver = nil
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        clearHotkeyTriggers()
        isRunning = false
    }

    func refresh() {
        stop()
        start()
    }

    func createScene() {
        let scene = SceneDefinition(name: "New Scene", intent: .custom)
        scenes.append(scene)
        persistScenes()
        activateScene(id: scene.id, reason: "Created scene", isManual: true)
    }

    func duplicateScene(_ scene: SceneDefinition) {
        var copy = scene
        copy.id = UUID()
        copy.name += " Copy"
        copy.isBuiltIn = false
        copy.createdBy = "user"
        copy.updatedAt = Date()
        scenes.append(copy)
        persistScenes()
    }

    func deleteScene(_ scene: SceneDefinition) {
        guard scene.isBuiltIn == false else { return }
        scenes.removeAll { $0.id == scene.id }
        if activeSceneID == scene.id {
            activeSceneID = scenes.first?.id
            resolvedScene = activeSceneID.flatMap { SceneResolver.resolve(sceneID: $0, scenes: scenes) }
        }
        persistScenes()
        persistRuntimeState()
    }

    func upsertScene(_ scene: SceneDefinition) {
        guard let index = scenes.firstIndex(where: { $0.id == scene.id }) else {
            scenes.append(scene)
            persistScenes()
            return
        }
        scenes[index] = scene
        persistScenes()
        if activeSceneID == scene.id {
            resolvedScene = SceneResolver.resolve(sceneID: scene.id, scenes: scenes)
        }
    }

    func testScene(_ scene: SceneDefinition) {
        upsertScene(scene)
        activateScene(id: scene.id, reason: "Scene test", isManual: true)
    }

    func revertToLastManualScene() {
        guard let lastManualSceneID, lastManualSceneID != activeSceneID else {
            return
        }
        activateScene(id: lastManualSceneID, reason: "Revert to last manual scene", isManual: true)
    }

    func resumeAutomaticScenes() {
        isSafeModeEnabled = false
        consecutiveFailureCount = 0
        appendHistory(
            SceneExecutionRecord(
                sceneID: activeSceneID,
                sceneName: activeSceneTitle,
                reason: "Resume automatic scenes",
                status: .success,
                detail: "Safe mode disabled"
            )
        )
        evaluateAutomaticTriggers(reason: "Automatic scenes resumed")
    }

    func reevaluateAutomaticTriggers(reason: String) {
        evaluateAutomaticTriggers(reason: reason)
    }

    func activateScene(id: UUID, reason: String, isManual: Bool = false) {
        guard isSafeModeEnabled == false || isManual else {
            appendHistory(
                SceneExecutionRecord(
                    sceneID: id,
                    sceneName: scenes.first(where: { $0.id == id })?.name ?? "Unknown Scene",
                    reason: reason,
                    status: .skipped,
                    detail: "Safe mode blocked automatic scene activation"
                )
            )
            return
        }
        guard let nextScene = SceneResolver.resolve(sceneID: id, scenes: scenes) else {
            return
        }

        guard activeSceneID != id || isManual else {
            return
        }

        let previousScene = resolvedScene
        resolvedScene = nextScene
        activeSceneID = id
        currentActivationReason = reason
        if isManual {
            lastManualSceneID = id
            sessionManualOverrides.removeAll()
        } else {
            noteAutomaticActivation(sceneID: id, now: Date(), reason: reason)
        }
        persistRuntimeState()

        Task {
            if let previousScene {
                await runActions(
                    previousScene.onExit,
                    scene: previousScene.definition,
                    reason: "Exit: \(reason)",
                    allowSessionOverrides: false
                )
            }
            let enterSucceeded = await runActions(
                nextScene.onEnter,
                scene: nextScene.definition,
                reason: reason,
                allowSessionOverrides: !isManual
            )
            if enterSucceeded {
                _ = await runActions(
                    nextScene.postActivate,
                    scene: nextScene.definition,
                    reason: "Post activate: \(reason)",
                    allowSessionOverrides: !isManual
                )
                consecutiveFailureCount = 0
                appendHistory(
                    SceneExecutionRecord(
                        sceneID: id,
                        sceneName: nextScene.definition.name,
                        reason: reason,
                        status: .success,
                        detail: "Activated scene"
                    )
                )
            }
        }
    }

    func noteManualActionOverride(_ actionName: String) {
        sessionManualOverrides.insert(actionName)
        appendHistory(
            SceneExecutionRecord(
                sceneID: activeSceneID,
                sceneName: activeSceneTitle,
                reason: "Manual user action",
                status: .skipped,
                detail: "Current session overrides scene action \(actionName)"
            )
        )
    }

    func previewScene(_ scene: SceneDefinition, availableScenes: [SceneDefinition]) -> ScenePreview? {
        let previewScenes = availableScenes.filter { $0.id != scene.id } + [scene]
        guard let resolved = SceneResolver.resolve(sceneID: scene.id, scenes: previewScenes) else {
            return nil
        }

        let phases: [ScenePreview.ActionPhase] = [
            ScenePreview.ActionPhase(title: "On Enter", actions: resolved.onEnter.map(previewAction)),
            ScenePreview.ActionPhase(title: "On Exit", actions: resolved.onExit.map(previewAction)),
            ScenePreview.ActionPhase(title: "On Fail", actions: resolved.onFail.map(previewAction)),
            ScenePreview.ActionPhase(title: "Post Activate", actions: resolved.postActivate.map(previewAction)),
        ]

        let triggerSummaries = scene.triggers.map(triggerSummary)
        return ScenePreview(
            definition: scene,
            resolved: resolved,
            triggerSummaries: triggerSummaries,
            actionPhases: phases,
            moduleSnapshots: runtimeContext.moduleSnapshots?() ?? []
        )
    }

    func promotedModules() -> [SceneModuleOverride] {
        (resolvedScene?.moduleOverrides ?? [])
            .filter { $0.visibility == .promoted && $0.state != .disabled }
            .sorted { ($0.panelOrder ?? .max) < ($1.panelOrder ?? .max) }
    }

    func onDemandModules() -> [SceneModuleOverride] {
        (resolvedScene?.moduleOverrides ?? [])
            .filter { $0.state == .onDemand && $0.visibility != .hidden }
            .sorted { ($0.panelOrder ?? .max) < ($1.panelOrder ?? .max) }
    }

    func pinnedActionItems() -> [ScenePinnedActionItem] {
        (resolvedScene?.moduleOverrides ?? [])
            .filter { $0.state != .disabled }
            .filter { $0.visibility != .hidden || !$0.pinnedActions.isEmpty }
            .flatMap { override in
            override.pinnedActions.map { rawValue in
                makePinnedActionItem(moduleID: override.moduleID, rawValue: rawValue)
            }
        }
    }

    func executePinnedAction(_ item: ScenePinnedActionItem) {
        guard let action = makePinnedSceneAction(from: item.rawValue) else {
            appendHistory(
                SceneExecutionRecord(
                    sceneID: activeSceneID,
                    sceneName: activeSceneTitle,
                    reason: "Pinned action",
                    status: .failed,
                    detail: "Unsupported pinned action \(item.rawValue)"
                )
            )
            return
        }

        Task {
            let result = await runAction(action)
            appendHistory(
                SceneExecutionRecord(
                    sceneID: activeSceneID,
                    sceneName: activeSceneTitle,
                    reason: "Pinned action",
                    status: result.success ? .success : .failed,
                    detail: result.detail
                )
            )
        }
    }

    func override(for moduleID: SceneModuleID) -> SceneModuleOverride? {
        resolvedScene?.moduleOverrides.first(where: { $0.moduleID == moduleID })
    }

    func isModuleVisible(_ moduleID: SceneModuleID) -> Bool {
        guard let override = override(for: moduleID) else {
            return true
        }
        guard override.visibility != .hidden, override.state != .disabled else {
            return false
        }
        if override.state == .onDemand {
            return override.visibility == .promoted
        }
        return true
    }

    var activeSceneTitle: String {
        resolvedScene?.definition.name ?? "No Scene"
    }

    var activeSceneReason: String {
        currentActivationReason
    }

    var isSafeModeActive: Bool {
        isSafeModeEnabled
    }

    var recentTriggerHistory: [SceneExecutionRecord] {
        history.filter { $0.reason == "Trigger fired" }
    }

    var recentActionHistory: [SceneExecutionRecord] {
        history.filter { $0.reason != "Trigger fired" }
    }

    func capabilitySnapshot(for moduleID: SceneModuleID) -> SceneModuleCapabilitySnapshot? {
        runtimeContext.moduleSnapshots?().first(where: { $0.moduleID == moduleID })
    }

    private func startObservers() {
        stop()
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self.handleApplicationActivated(app)
        }
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.evaluateAutomaticTriggers(reason: "Display configuration changed")
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.evaluateAutomaticTriggers(reason: "System woke")
        }
    }

    private func handleApplicationActivated(_ app: NSRunningApplication) {
        let now = Date()
        var matchedTriggerIDs = Set<UUID>()
        let matches = scenes.compactMap { scene -> SceneMatchCandidate? in
            let triggers = scene.triggers.filter { $0.enabled && $0.type == .appFocus }
            for trigger in triggers {
                let bundleMatch = trigger.match.primary.caseInsensitiveCompare(app.bundleIdentifier ?? "") == .orderedSame
                let appNameMatch = trigger.match.secondary.caseInsensitiveCompare(app.localizedName ?? "") == .orderedSame
                guard bundleMatch || appNameMatch else { continue }
                guard triggerIsEligible(trigger, now: now) else { continue }
                let specificity = bundleMatch ? 200 + trigger.match.primary.count : 100 + trigger.match.secondary.count
                matchedTriggerIDs.insert(trigger.id)
                return SceneMatchCandidate(
                    scene: scene,
                    trigger: trigger,
                    specificity: specificity,
                    reasonDetail: "App focus: \(app.localizedName ?? scene.name)"
                )
            }
            return nil
        }
        clearStaleFirstMatches(for: [.appFocus], keeping: matchedTriggerIDs)

        guard let winner = selectWinner(from: matches) else {
            return
        }

        markTriggerFired(winner.trigger, at: now)
        activateScene(id: winner.scene.id, reason: winner.reasonDetail)
    }

    @discardableResult
    private func runActions(
        _ actions: [SceneAction],
        scene: SceneDefinition,
        reason: String,
        allowSessionOverrides: Bool
    ) async -> Bool {
        var rollbackStack: [() -> Void] = []
        for action in actions {
            if allowSessionOverrides,
               action.type == .atlasAction,
               let actionName = action.params["name"],
               sessionManualOverrides.contains(actionName) {
                appendHistory(
                    SceneExecutionRecord(
                        sceneID: scene.id,
                        sceneName: scene.name,
                        reason: reason,
                        status: .skipped,
                        detail: "Skipped \(action.title) because a manual user action overrode \(actionName) for this session"
                    )
                )
                continue
            }

            let result = await runActionWithRetry(action)
            if let rollback = result.rollback {
                rollbackStack.append(rollback)
            }
            if result.success {
                appendHistory(
                    SceneExecutionRecord(
                        sceneID: scene.id,
                        sceneName: scene.name,
                        reason: reason,
                        status: .success,
                        detail: result.detail.isEmpty ? "Executed action: \(action.title)" : result.detail
                    )
                )
            }
            if result.success == false {
                consecutiveFailureCount += 1
                appendHistory(
                    SceneExecutionRecord(
                        sceneID: scene.id,
                        sceneName: scene.name,
                        reason: reason,
                        status: .failed,
                        detail: result.detail.isEmpty ? "Failed action: \(action.title)" : result.detail
                    )
                )
                if action.failurePolicy == .rollback {
                    for rollback in rollbackStack.reversed() {
                        rollback()
                    }
                }
                if !scene.onFail.isEmpty {
                    _ = await runActions(
                        scene.onFail,
                        scene: scene,
                        reason: "onFail for \(reason)",
                        allowSessionOverrides: false
                    )
                }
                if consecutiveFailureCount >= 3 {
                    isSafeModeEnabled = true
                    appendHistory(
                        SceneExecutionRecord(
                            sceneID: scene.id,
                            sceneName: scene.name,
                            reason: reason,
                            status: .failed,
                            detail: "Safe mode enabled after repeated scene failures"
                        )
                    )
                }
                if action.failurePolicy == .stop || action.failurePolicy == .rollback {
                    return false
                }
            }
        }
        return true
    }

    private struct SceneActionRunResult {
        let success: Bool
        let detail: String
        let rollback: (() -> Void)?
    }

    private func runActionWithRetry(_ action: SceneAction) async -> SceneActionRunResult {
        let totalAttempts = max(1, action.retryPolicy.retryCount + 1)
        var lastResult: SceneActionRunResult?

        for attempt in 1...totalAttempts {
            let result = await runAction(action)
            if result.success {
                if attempt == 1 {
                    return result
                }
                return SceneActionRunResult(
                    success: true,
                    detail: "\(result.detail) after \(attempt) attempts",
                    rollback: result.rollback
                )
            }
            lastResult = result
        }

        if totalAttempts > 1, let lastResult {
            return SceneActionRunResult(
                success: false,
                detail: "\(lastResult.detail) after \(totalAttempts) attempts",
                rollback: lastResult.rollback
            )
        }

        return lastResult ?? SceneActionRunResult(success: false, detail: "Action failed", rollback: nil)
    }

    private func runAction(_ action: SceneAction) async -> SceneActionRunResult {
        switch action.type {
        case .atlasAction:
            return runAtlasAction(action)
        case .systemAction:
            return runSystemAction(action)
        case .scriptAction:
            guard let command = action.params["command"], let kind = action.params["kind"] else {
                return SceneActionRunResult(success: false, detail: "Missing automation command parameters", rollback: nil)
            }
            let automation = CustomAutomationCommand(
                title: action.title,
                command: command,
                kind: CustomAutomationKind(rawValue: kind) ?? .shell,
                timeoutSeconds: action.timeout,
                requiresConfirmation: false
            )
            guard let runAutomation = runtimeContext.runAutomation else {
                return SceneActionRunResult(success: false, detail: "Automation runner unavailable", rollback: nil)
            }
            let result = await runAutomation(automation)
            return SceneActionRunResult(
                success: result.exitCode == 0,
                detail: result.exitCode == 0
                    ? "Automation succeeded: \(actionSummary(action))"
                    : (result.standardError.isEmpty ? "Automation failed (\(actionSummary(action))) with exit code \(result.exitCode)" : "\(actionSummary(action)) failed: \(result.standardError)"),
                rollback: nil
            )
        case .aiSkillAction:
            guard let title = action.params["title"], let runSkillNamed = runtimeContext.runSkillNamed else {
                return SceneActionRunResult(success: false, detail: "AI skill action unavailable", rollback: nil)
            }
            let succeeded = await runSkillNamed(title)
            return SceneActionRunResult(
                success: succeeded,
                detail: succeeded ? "AI skill succeeded: \(actionSummary(action))" : "AI skill failed: \(actionSummary(action))",
                rollback: nil
            )
        }
    }

    private func runAtlasAction(_ action: SceneAction) -> SceneActionRunResult {
        switch action.params["name"] {
        case "toggle-keep-awake":
            let wasActive = runtimeContext.currentKeepAwakeActive?() ?? false
            runtimeContext.toggleKeepAwake?()
            let rollback = { [runtimeContext] in
                let isActive = runtimeContext.currentKeepAwakeActive?() ?? wasActive
                if isActive != wasActive {
                    runtimeContext.toggleKeepAwake?()
                }
            }
            return SceneActionRunResult(success: runtimeContext.toggleKeepAwake != nil, detail: "Toggled keep awake", rollback: rollback)
        case "toggle-presentation-mode":
            let wasActive = runtimeContext.currentPresentationModeActive?() ?? false
            runtimeContext.togglePresentationMode?()
            let rollback = { [runtimeContext] in
                let isActive = runtimeContext.currentPresentationModeActive?() ?? wasActive
                if isActive != wasActive {
                    runtimeContext.togglePresentationMode?()
                }
            }
            return SceneActionRunResult(success: runtimeContext.togglePresentationMode != nil, detail: "Toggled presentation mode", rollback: rollback)
        case "open-hand-mirror":
            let permission = runtimeContext.currentCameraPermissionState?() ?? .notDetermined
            switch permission {
            case .authorized:
                break
            case .notDetermined:
                return SceneActionRunResult(success: false, detail: "Camera permission has not been granted yet", rollback: nil)
            case .denied, .restricted:
                return SceneActionRunResult(success: false, detail: "Camera permission is unavailable", rollback: nil)
            }
            runtimeContext.openHandMirror?()
            return SceneActionRunResult(success: runtimeContext.openHandMirror != nil, detail: "Opened camera preview", rollback: nil)
        case "refresh-displays":
            runtimeContext.refreshDisplays?()
            return SceneActionRunResult(success: runtimeContext.refreshDisplays != nil, detail: "Refreshed displays", rollback: nil)
        case "apply-audio-preset":
            if let title = action.params["title"] {
                let previousRoute = runtimeContext.currentAudioRoute?()
                let presets = runtimeContext.availableAudioPresetTitles?() ?? []
                guard presets.contains(where: { $0.caseInsensitiveCompare(title) == .orderedSame }) else {
                    return SceneActionRunResult(success: false, detail: "Audio preset \(title) was not found", rollback: nil)
                }
                guard runtimeContext.applyAudioPreset != nil else {
                    return SceneActionRunResult(success: false, detail: "Audio Hub is unavailable", rollback: nil)
                }
                runtimeContext.applyAudioPreset?(title)
                let rollback = previousRoute.flatMap { previousRoute in
                    runtimeContext.restoreAudioRoute.map { restoreAudioRoute in
                        { restoreAudioRoute(previousRoute) }
                    }
                }
                return SceneActionRunResult(success: true, detail: "Applied audio preset \(title)", rollback: rollback)
            }
            return SceneActionRunResult(success: false, detail: "Missing audio preset title", rollback: nil)
        case "save-note":
            if let title = action.params["title"], let body = action.params["body"] {
                guard runtimeContext.saveTextToScratchpad != nil else {
                    return SceneActionRunResult(success: false, detail: "Scratchpad is unavailable", rollback: nil)
                }
                let noteID = runtimeContext.saveTextToScratchpad?(title, body)
                let rollback = noteID.flatMap { noteID in
                    runtimeContext.deleteScratchpadNote.map { deleteScratchpadNote in
                        { deleteScratchpadNote(noteID) }
                    }
                }
                return SceneActionRunResult(success: noteID != nil, detail: noteID != nil ? "Saved note to Scratchpad" : "Scratchpad did not create a note", rollback: rollback)
            }
            return SceneActionRunResult(success: false, detail: "Missing note content", rollback: nil)
        default:
            return SceneActionRunResult(success: false, detail: "Unknown Atlas action", rollback: nil)
        }
    }

    private func runSystemAction(_ action: SceneAction) -> SceneActionRunResult {
        if let urlString = action.params["url"], let url = URL(string: urlString) {
            let opened = NSWorkspace.shared.open(url)
            return SceneActionRunResult(
                success: opened,
                detail: opened ? "Opened \(url.absoluteString)" : "Failed to open \(url.absoluteString)",
                rollback: nil
            )
        }
        if let appPath = action.params["appPath"] {
            guard FileManager.default.fileExists(atPath: appPath) else {
                return SceneActionRunResult(success: false, detail: "App path does not exist: \(appPath)", rollback: nil)
            }
            let opened = NSWorkspace.shared.open(URL(fileURLWithPath: appPath))
            return SceneActionRunResult(
                success: opened,
                detail: opened ? "Opened app at \(appPath)" : "Failed to open app at \(appPath)",
                rollback: nil
            )
        }
        return SceneActionRunResult(success: false, detail: "Missing system action target", rollback: nil)
    }

    private func registerHotkeyTriggers() {
        clearHotkeyTriggers()
        for scene in scenes {
            for trigger in scene.triggers where trigger.enabled && trigger.type == .hotkey {
                guard let keyCode = Int(trigger.match.primary),
                      let modifiers = UInt(trigger.match.secondary) else {
                    continue
                }
                runtimeContext.registerSceneHotkey?(keyCode, modifiers) { [weak self] in
                    self?.activateScene(id: scene.id, reason: "Hotkey: \(scene.name)", isManual: true)
                }
                registeredHotkeys.append((keyCode: keyCode, modifiers: modifiers))
            }
        }
    }

    private func clearHotkeyTriggers() {
        for item in registeredHotkeys {
            runtimeContext.unregisterSceneHotkey?(item.keyCode, item.modifiers)
        }
        registeredHotkeys.removeAll()
    }

    private func startScheduleTimer() {
        scheduleTimer?.invalidate()
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.evaluateAutomaticTriggers(reason: "Timer tick")
        }
        if let scheduleTimer {
            RunLoop.main.add(scheduleTimer, forMode: .common)
        }
    }

    private func evaluateAutomaticTriggers(reason: String) {
        guard isSafeModeEnabled == false else { return }
        let now = Date()
        let audioNames = runtimeContext.currentAudioDeviceNames?() ?? []
        let bluetoothNames = runtimeContext.currentBluetoothDeviceNames?() ?? []
        let networkTokens = runtimeContext.currentNetworkTriggerTokens?() ?? []
        let displayTokens = runtimeContext.currentDisplayTriggerTokens?() ?? []
        let powerTokens = runtimeContext.currentPowerStateTriggerTokens?() ?? []
        let idleSeconds = runtimeContext.currentIdleSeconds?()
        var matchedTriggerIDs = Set<UUID>()

        let matches = scenes.compactMap { scene -> SceneMatchCandidate? in
            for trigger in scene.triggers where trigger.enabled {
                switch trigger.type {
                case .schedule:
                    guard scheduleMatches(trigger, now: now), triggerIsEligible(trigger, now: now) else { continue }
                    matchedTriggerIDs.insert(trigger.id)
                    let specificity = trigger.match.secondary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 10 : 20
                    return SceneMatchCandidate(scene: scene, trigger: trigger, specificity: specificity, reasonDetail: "Schedule: \(trigger.match.primary)")
                case .audioDevice:
                    if let match = triggerNameMatch(trigger, candidates: audioNames), triggerIsEligible(trigger, now: now) {
                        matchedTriggerIDs.insert(trigger.id)
                        return SceneMatchCandidate(scene: scene, trigger: trigger, specificity: match.specificity, reasonDetail: "Audio device: \(match.matchedValue)")
                    }
                case .bluetoothDevice:
                    if let match = triggerNameMatch(trigger, candidates: bluetoothNames), triggerIsEligible(trigger, now: now) {
                        matchedTriggerIDs.insert(trigger.id)
                        return SceneMatchCandidate(scene: scene, trigger: trigger, specificity: match.specificity, reasonDetail: "Bluetooth device: \(match.matchedValue)")
                    }
                case .network:
                    if let match = triggerNameMatch(trigger, candidates: networkTokens), triggerIsEligible(trigger, now: now) {
                        matchedTriggerIDs.insert(trigger.id)
                        return SceneMatchCandidate(scene: scene, trigger: trigger, specificity: match.specificity, reasonDetail: "Network: \(match.matchedValue)")
                    }
                case .display:
                    if let match = triggerNameMatch(trigger, candidates: displayTokens), triggerIsEligible(trigger, now: now) {
                        matchedTriggerIDs.insert(trigger.id)
                        return SceneMatchCandidate(scene: scene, trigger: trigger, specificity: match.specificity, reasonDetail: "Display: \(match.matchedValue)")
                    }
                case .powerState:
                    if let match = triggerNameMatch(trigger, candidates: powerTokens), triggerIsEligible(trigger, now: now) {
                        matchedTriggerIDs.insert(trigger.id)
                        return SceneMatchCandidate(scene: scene, trigger: trigger, specificity: match.specificity, reasonDetail: "Power state: \(match.matchedValue)")
                    }
                case .idleState:
                    if let match = idleStateMatch(trigger, idleSeconds: idleSeconds), triggerIsEligible(trigger, now: now) {
                        matchedTriggerIDs.insert(trigger.id)
                        return SceneMatchCandidate(scene: scene, trigger: trigger, specificity: match.specificity, reasonDetail: match.reasonDetail)
                    }
                default:
                    continue
                }
            }
            return nil
        }
        clearStaleFirstMatches(
            for: [.schedule, .audioDevice, .bluetoothDevice, .network, .display, .powerState, .idleState],
            keeping: matchedTriggerIDs
        )

        guard let winner = selectWinner(from: matches) else {
            return
        }

        markTriggerFired(winner.trigger, at: now)
        activateScene(id: winner.scene.id, reason: winner.reasonDetail)
    }

    private func triggerNameMatch(_ trigger: SceneTrigger, candidates: [String]) -> (specificity: Int, matchedValue: String)? {
        let accepted = ([trigger.match.primary, trigger.match.secondary] + trigger.match.values)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !accepted.isEmpty else { return nil }
        let haystack = candidates.map { ($0, $0.lowercased()) }
        let matches = accepted.compactMap { needle -> (Int, String)? in
            guard let matchedValue = haystack.first(where: { $0.1.contains(needle) })?.0 else {
                return nil
            }
            return (needle.count, matchedValue)
        }
        guard let bestMatch = matches.max(by: { $0.0 < $1.0 }) else { return nil }
        return (bestMatch.0, bestMatch.1)
    }

    private func scheduleMatches(_ trigger: SceneTrigger, now: Date) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let current = formatter.string(from: now)
        let start = trigger.match.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = trigger.match.secondary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !start.isEmpty else { return false }
        if end.isEmpty {
            return current == start
        }
        return current >= start && current <= end
    }

    private func triggerSummary(_ trigger: SceneTrigger) -> String {
        let matchParts = ([trigger.match.primary, trigger.match.secondary] + trigger.match.values)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var summary = trigger.type.rawValue
        if !matchParts.isEmpty {
            summary += " • " + matchParts.joined(separator: ", ")
        }
        if let debounce = trigger.debounce {
            summary += " • debounce \(Int(debounce))s"
        }
        if let cooldown = trigger.cooldown {
            summary += " • cooldown \(Int(cooldown))s"
        }
        if !trigger.enabled {
            summary += " • disabled"
        }
        return summary
    }

    private func idleStateMatch(
        _ trigger: SceneTrigger,
        idleSeconds: TimeInterval?
    ) -> (specificity: Int, reasonDetail: String)? {
        guard let idleSeconds else { return nil }
        let mode = trigger.match.primary.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let threshold = Double(trigger.match.secondary.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 60
        switch mode {
        case "idle":
            guard idleSeconds >= threshold else { return nil }
            return (Int(threshold), "Idle state: idle for \(Int(idleSeconds))s")
        case "active":
            guard idleSeconds < threshold else { return nil }
            return (Int(threshold), "Idle state: active within \(Int(threshold))s")
        default:
            return nil
        }
    }

    private func actionSummary(_ action: SceneAction) -> String {
        let retrySummary = action.retryPolicy == .none ? nil : action.retryPolicy.title
        let params = action.params
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
        var parts: [String] = []
        if !params.isEmpty {
            parts.append(params.joined(separator: ", "))
        }
        parts.append("timeout=\(Int(action.timeout))s")
        if let retrySummary {
            parts.append(retrySummary)
        }
        if parts.isEmpty {
            return "\(action.title) [\(action.type.rawValue)]"
        }
        return "\(action.title) [\(action.type.rawValue)] • \(parts.joined(separator: " • "))"
    }

    private func makePinnedActionItem(moduleID: SceneModuleID, rawValue: String) -> ScenePinnedActionItem {
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        let name = parts.first ?? rawValue
        let argument = parts.count > 1 ? parts[1] : nil
        let title: String
        let isEnabled: Bool

        switch name {
        case "toggle-keep-awake":
            title = "Keep Awake"
            isEnabled = runtimeContext.toggleKeepAwake != nil
        case "toggle-presentation-mode":
            title = "Presentation Mode"
            isEnabled = runtimeContext.togglePresentationMode != nil
        case "open-hand-mirror":
            title = "Camera Preview"
            isEnabled = runtimeContext.openHandMirror != nil
        case "refresh-displays":
            title = "Refresh Displays"
            isEnabled = runtimeContext.refreshDisplays != nil
        case "apply-audio-preset":
            title = argument.map { "Preset: \($0)" } ?? "Audio Preset"
            let presets = runtimeContext.availableAudioPresetTitles?() ?? []
            isEnabled = argument != nil && presets.contains(where: { $0.caseInsensitiveCompare(argument ?? "") == .orderedSame })
        default:
            title = rawValue
            isEnabled = false
        }

        return ScenePinnedActionItem(moduleID: moduleID, rawValue: rawValue, title: title, isEnabled: isEnabled)
    }

    private func makePinnedSceneAction(from rawValue: String) -> SceneAction? {
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        let name = parts.first ?? rawValue
        let argument = parts.count > 1 ? parts[1] : nil

        switch name {
        case "toggle-keep-awake", "toggle-presentation-mode", "open-hand-mirror", "refresh-displays":
            return SceneAction(title: name, type: .atlasAction, params: ["name": name])
        case "apply-audio-preset":
            guard let argument, !argument.isEmpty else { return nil }
            return SceneAction(title: "Apply \(argument)", type: .atlasAction, params: ["name": name, "title": argument])
        default:
            return nil
        }
    }

    private func previewAction(_ action: SceneAction) -> ScenePreview.ActionPreview {
        switch action.type {
        case .atlasAction:
            return previewAtlasAction(action)
        case .systemAction:
            return previewSystemAction(action)
        case .scriptAction:
            guard action.params["command"] != nil, action.params["kind"] != nil else {
                return .init(summary: actionSummary(action), status: .unavailable, detail: "Missing command or kind")
            }
            let ready = runtimeContext.runAutomation != nil
            return .init(
                summary: actionSummary(action),
                status: ready ? .ready : .unavailable,
                detail: ready ? "Automation runner is available" : "Automation runner is unavailable"
            )
        case .aiSkillAction:
            guard let title = action.params["title"], !title.isEmpty else {
                return .init(summary: actionSummary(action), status: .unavailable, detail: "Missing skill title")
            }
            guard runtimeContext.runSkillNamed != nil else {
                return .init(summary: actionSummary(action), status: .unavailable, detail: "Skill runner is unavailable")
            }
            let availableTitles = runtimeContext.availableSkillTitles?() ?? []
            let exists = availableTitles.isEmpty || availableTitles.contains(where: { $0.caseInsensitiveCompare(title) == .orderedSame })
            return .init(
                summary: actionSummary(action),
                status: exists ? .ready : .attention,
                detail: exists ? "Skill can be invoked" : "Skill title was not found in the current skill store"
            )
        }
    }

    private func previewAtlasAction(_ action: SceneAction) -> ScenePreview.ActionPreview {
        let summary = actionSummary(action)
        switch action.params["name"] {
        case "toggle-keep-awake":
            return .init(summary: summary, status: runtimeContext.toggleKeepAwake != nil ? .ready : .unavailable, detail: runtimeContext.toggleKeepAwake != nil ? "Keep Awake control is available" : "Keep Awake control is unavailable")
        case "toggle-presentation-mode":
            return .init(summary: summary, status: runtimeContext.togglePresentationMode != nil ? .ready : .unavailable, detail: runtimeContext.togglePresentationMode != nil ? "Presentation Mode control is available" : "Presentation Mode control is unavailable")
        case "open-hand-mirror":
            let permission = runtimeContext.currentCameraPermissionState?() ?? .notDetermined
            switch permission {
            case .authorized:
                return .init(summary: summary, status: .ready, detail: "Camera permission is authorized")
            case .notDetermined:
                return .init(summary: summary, status: .attention, detail: "Camera permission has not been granted yet")
            case .denied, .restricted:
                return .init(summary: summary, status: .unavailable, detail: "Camera permission is unavailable")
            }
        case "refresh-displays":
            return .init(summary: summary, status: runtimeContext.refreshDisplays != nil ? .ready : .unavailable, detail: runtimeContext.refreshDisplays != nil ? "Display refresh is available" : "Display refresh is unavailable")
        case "apply-audio-preset":
            guard let title = action.params["title"], !title.isEmpty else {
                return .init(summary: summary, status: .unavailable, detail: "Missing audio preset title")
            }
            guard runtimeContext.applyAudioPreset != nil else {
                return .init(summary: summary, status: .unavailable, detail: "Audio Hub is unavailable")
            }
            let presets = runtimeContext.availableAudioPresetTitles?() ?? []
            let exists = presets.contains(where: { $0.caseInsensitiveCompare(title) == .orderedSame })
            return .init(summary: summary, status: exists ? .ready : .attention, detail: exists ? "Preset exists" : "Preset title was not found in Audio Hub")
        case "save-note":
            let ready = runtimeContext.saveTextToScratchpad != nil
            let hasContent = action.params["title"] != nil && action.params["body"] != nil
            let status: ScenePreview.DryRunStatus = !ready || !hasContent ? .unavailable : .ready
            let detail = !ready ? "Scratchpad is unavailable" : (hasContent ? "Scratchpad note can be created" : "Missing note title or body")
            return .init(summary: summary, status: status, detail: detail)
        default:
            return .init(summary: summary, status: .unavailable, detail: "Unknown Atlas action")
        }
    }

    private func previewSystemAction(_ action: SceneAction) -> ScenePreview.ActionPreview {
        let summary = actionSummary(action)
        if let urlString = action.params["url"] {
            return .init(summary: summary, status: URL(string: urlString) != nil ? .ready : .unavailable, detail: URL(string: urlString) != nil ? "URL is valid" : "URL is invalid")
        }
        if let appPath = action.params["appPath"] {
            let exists = FileManager.default.fileExists(atPath: appPath)
            return .init(summary: summary, status: exists ? .ready : .attention, detail: exists ? "App path exists" : "App path does not exist on disk")
        }
        return .init(summary: summary, status: .unavailable, detail: "Missing system target")
    }

    private func selectWinner(from candidates: [SceneMatchCandidate]) -> SceneMatchCandidate? {
        candidates.max { lhs, rhs in
            if lhs.scene.priority != rhs.scene.priority {
                return lhs.scene.priority < rhs.scene.priority
            }
            if lhs.specificity != rhs.specificity {
                return lhs.specificity < rhs.specificity
            }
            let lhsManualBias = lhs.scene.id == lastManualSceneID ? 1 : 0
            let rhsManualBias = rhs.scene.id == lastManualSceneID ? 1 : 0
            if lhsManualBias != rhsManualBias {
                return lhsManualBias < rhsManualBias
            }
            return lhs.scene.name < rhs.scene.name
        }
    }

    private func triggerIsEligible(_ trigger: SceneTrigger, now: Date) -> Bool {
        if let cooldown = trigger.cooldown,
           let lastFired = triggerLastFiredAt[trigger.id],
           now.timeIntervalSince(lastFired) < cooldown {
            return false
        }

        if let debounce = trigger.debounce {
            let firstMatched = triggerFirstMatchedAt[trigger.id] ?? now
            triggerFirstMatchedAt[trigger.id] = firstMatched
            if now.timeIntervalSince(firstMatched) < debounce {
                return false
            }
        }

        return true
    }

    private func clearStaleFirstMatches(for types: [SceneTriggerType], keeping matchedTriggerIDs: Set<UUID>) {
        let eligibleTriggerIDs = Set(
            scenes
                .flatMap(\.triggers)
                .filter { $0.enabled && types.contains($0.type) }
                .map(\.id)
        )
        for triggerID in eligibleTriggerIDs where matchedTriggerIDs.contains(triggerID) == false {
            triggerFirstMatchedAt.removeValue(forKey: triggerID)
        }
    }

    private func markTriggerFired(_ trigger: SceneTrigger, at now: Date) {
        triggerLastFiredAt[trigger.id] = now
        triggerFirstMatchedAt[trigger.id] = now
        persistRuntimeState()
        appendHistory(
            SceneExecutionRecord(
                sceneID: activeSceneID,
                sceneName: activeSceneTitle,
                reason: "Trigger fired",
                status: .success,
                detail: triggerSummary(trigger),
                timestamp: now
            )
        )
    }

    private func noteAutomaticActivation(sceneID: UUID, now: Date, reason: String) {
        recentAutomaticActivations.append(SceneActivationEvent(sceneID: sceneID, timestamp: now))
        recentAutomaticActivations = recentAutomaticActivations.filter { now.timeIntervalSince($0.timestamp) <= 30 }

        guard recentAutomaticActivations.count >= 4 else {
            return
        }

        let distinctSceneCount = Set(recentAutomaticActivations.map(\.sceneID)).count
        guard distinctSceneCount >= 2 else {
            return
        }

        isSafeModeEnabled = true
        appendHistory(
            SceneExecutionRecord(
                sceneID: sceneID,
                sceneName: scenes.first(where: { $0.id == sceneID })?.name ?? activeSceneTitle,
                reason: reason,
                status: .failed,
                detail: "Safe mode enabled after rapid automatic scene switching"
            )
        )
    }

    private func persistScenes() {
        do {
            try store.saveScenes(scenes)
        } catch {
            appendHistory(
                SceneExecutionRecord(
                    sceneID: activeSceneID,
                    sceneName: activeSceneTitle,
                    reason: "Save scenes",
                    status: .failed,
                    detail: error.localizedDescription
                )
            )
        }
    }

    private func persistRuntimeState() {
        do {
            try store.saveRuntimeState(
                SceneRuntimeState(
                    activeSceneID: activeSceneID,
                    lastManualSceneID: lastManualSceneID,
                    activeSceneReason: currentActivationReason,
                    triggerLastFiredAt: triggerLastFiredAt,
                    triggerFirstMatchedAt: triggerFirstMatchedAt
                )
            )
        } catch {
            appendHistory(
                SceneExecutionRecord(
                    sceneID: activeSceneID,
                    sceneName: activeSceneTitle,
                    reason: "Save scene runtime state",
                    status: .failed,
                    detail: error.localizedDescription
                )
            )
        }
    }

    private func appendHistory(_ record: SceneExecutionRecord) {
        history.insert(record, at: 0)
        history = Array(history.prefix(100))
        try? store.appendHistory(record)
    }
}

struct SceneCenterPanel: View {
    @ObservedObject var coordinator: SceneCoordinator
    let onOpenEditor: () -> Void
    let onOpenDiagnostics: () -> Void
    let onRevealModule: (SceneModuleID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Scenes", systemImage: "square.stack.3d.up")
                    .font(.headline)
                Spacer()
                Button("Editor", action: onOpenEditor)
                Button("Diagnostics", action: onOpenDiagnostics)
            }

            Picker("Current Scene", selection: Binding(
                get: { coordinator.activeSceneID ?? coordinator.scenes.first?.id },
                set: { newValue in
                    if let newValue {
                        coordinator.activateScene(id: newValue, reason: "Manual picker", isManual: true)
                    }
                }
            )) {
                ForEach(coordinator.scenes) { scene in
                    Text(scene.name).tag(Optional(scene.id))
                }
            }
            .pickerStyle(.segmented)

            Text("Reason: \(coordinator.activeSceneReason)")
                .foregroundColor(.secondary)
                .font(.caption)

            if coordinator.isSafeModeActive {
                Label("Safe mode is active. Automatic scene switching is paused.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            HStack(spacing: 8) {
                if coordinator.lastManualSceneID != nil, coordinator.lastManualSceneID != coordinator.activeSceneID {
                    Button("Revert") {
                        coordinator.revertToLastManualScene()
                    }
                }
                if coordinator.isSafeModeActive {
                    Button("Resume Auto") {
                        coordinator.resumeAutomaticScenes()
                    }
                }
            }

            if !coordinator.promotedModules().isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(coordinator.promotedModules()) { override in
                            Label(override.moduleID.title, systemImage: symbol(for: override.moduleID))
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            if !coordinator.pinnedActionItems().isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Actions")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    FlowLayout(spacing: 8) {
                        ForEach(coordinator.pinnedActionItems()) { item in
                            Button(item.title) {
                                coordinator.executePinnedAction(item)
                            }
                            .disabled(!item.isEnabled)
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if !coordinator.onDemandModules().isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("On-Demand Modules")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    FlowLayout(spacing: 8) {
                        ForEach(coordinator.onDemandModules()) { override in
                            Button(override.moduleID.title) {
                                onRevealModule(override.moduleID)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private func symbol(for moduleID: SceneModuleID) -> String {
        switch moduleID {
        case .audioHub:
            return "speaker.wave.2"
        case .flowInbox:
            return "tray.full"
        case .cameraPreview:
            return "camera"
        case .scratchpad:
            return "note.text"
        case .clipboard:
            return "doc.on.clipboard"
        case .screenshot:
            return "crop"
        case .systemUtilities:
            return "switch.2"
        default:
            return "square.stack.3d.up"
        }
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SceneDiagnosticsView: View {
    @ObservedObject var coordinator: SceneCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Scene Diagnostics", systemImage: "stethoscope")
                .font(.headline)

            if let resolved = coordinator.resolvedScene {
                Text("Active: \(resolved.definition.name)")
                    .font(.subheadline.weight(.semibold))
                Text("Intent: \(resolved.definition.intent.title)")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text("Reason: \(coordinator.activeSceneReason)")
                    .foregroundColor(.secondary)
                    .font(.caption)

                if coordinator.isSafeModeActive {
                    Label("Safe mode is active", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                Divider()

                Text("Effective Modules")
                    .font(.subheadline.weight(.semibold))

                ForEach(resolved.moduleOverrides) { override in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(override.moduleID.title)
                            Spacer()
                            Text("\(override.visibility.rawValue) • \(override.state.rawValue)")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        if let panelOrder = override.panelOrder {
                            Text("Panel Order: \(panelOrder)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if !override.pinnedActions.isEmpty {
                            Text("Pinned Actions: \(override.pinnedActions.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if !override.settings.isEmpty {
                            Text("Settings: \(override.settings.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Divider()

                Text("Behavior Rules")
                    .font(.subheadline.weight(.semibold))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Screenshots to Inbox: \(resolved.behaviorRules.newScreenshotsGoToInbox ? "On" : "Off")")
                    Text("Prefer Inbox Favorites: \(resolved.behaviorRules.preferInboxFavorites ? "On" : "Off")")
                    Text("Prioritize Recent Content: \(resolved.behaviorRules.prioritizeRecentContent ? "On" : "Off")")
                    if !resolved.behaviorRules.promoteCommandPaletteCategory.isEmpty {
                        Text("Promoted Command Category: \(resolved.behaviorRules.promoteCommandPaletteCategory)")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Divider()

            Text("Recent Trigger History")
                .font(.subheadline.weight(.semibold))
            recordList(coordinator.recentTriggerHistory, emptyText: "No trigger events yet")

            Divider()

            Text("Recent Action Results")
                .font(.subheadline.weight(.semibold))
            recordList(coordinator.recentActionHistory, emptyText: "No scene actions or activations yet")
        }
        .padding()
        .frame(minWidth: 420, minHeight: 420)
    }

    @ViewBuilder
    private func recordList(_ records: [SceneExecutionRecord], emptyText: String) -> some View {
        ScrollView {
            if records.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(record.sceneName)
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text(record.timestamp.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                SceneRecordStatusLabel(status: record.status)
                            }
                            Text(record.reason)
                                .font(.caption)
                            Text(record.detail)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

struct SceneEditorView: View {
    @ObservedObject var coordinator: SceneCoordinator
    @State private var selectedSceneID: UUID?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Scenes")
                        .font(.headline)
                    Spacer()
                    Button(action: coordinator.createScene) {
                        Image(systemName: "plus")
                    }
                }

                List(selection: Binding(
                    get: { selectedSceneID },
                    set: { selectedSceneID = $0 }
                )) {
                    ForEach(coordinator.scenes) { scene in
                        HStack {
                            Image(systemName: scene.icon)
                            Text(scene.name)
                            Spacer()
                            if scene.isBuiltIn {
                                Text("Built-in")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tag(scene.id)
                    }
                }
            }
            .frame(minWidth: 220)
            .padding()

            if let scene = selectedScene {
                SceneDetailEditor(
                    scene: scene,
                    availableScenes: coordinator.scenes,
                    moduleCapability: { coordinator.capabilitySnapshot(for: $0) },
                    makePreview: { coordinator.previewScene($0, availableScenes: $1) },
                    onSave: { coordinator.upsertScene($0) },
                    onTest: { coordinator.testScene($0) },
                    onDuplicate: { coordinator.duplicateScene(scene) },
                    onDelete: { coordinator.deleteScene(scene) }
                )
            } else {
                Text("Select a scene")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            selectedSceneID = selectedSceneID ?? coordinator.scenes.first?.id
        }
        .frame(minWidth: 860, minHeight: 560)
    }

    private var selectedScene: SceneDefinition? {
        if let selectedSceneID {
            return coordinator.scenes.first(where: { $0.id == selectedSceneID })
        }
        return nil
    }
}

private struct SceneDetailEditor: View {
    @State private var draft: SceneDefinition
    @State private var preview: ScenePreview?
    @State private var isShowingPreview = false
    let availableScenes: [SceneDefinition]
    let moduleCapability: (SceneModuleID) -> SceneModuleCapabilitySnapshot?
    let makePreview: (SceneDefinition, [SceneDefinition]) -> ScenePreview?
    let onSave: (SceneDefinition) -> Void
    let onTest: (SceneDefinition) -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    init(
        scene: SceneDefinition,
        availableScenes: [SceneDefinition],
        moduleCapability: @escaping (SceneModuleID) -> SceneModuleCapabilitySnapshot?,
        makePreview: @escaping (SceneDefinition, [SceneDefinition]) -> ScenePreview?,
        onSave: @escaping (SceneDefinition) -> Void,
        onTest: @escaping (SceneDefinition) -> Void,
        onDuplicate: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        _draft = State(initialValue: scene)
        self.availableScenes = availableScenes
        self.moduleCapability = moduleCapability
        self.makePreview = makePreview
        self.onSave = onSave
        self.onTest = onTest
        self.onDuplicate = onDuplicate
        self.onDelete = onDelete
    }

    var body: some View {
        Form {
            Section("Basics") {
                TextField("Name", text: $draft.name)
                TextField("Icon", text: $draft.icon)
                TextField(
                    "Tags",
                    text: Binding(
                        get: { draft.tags.joined(separator: ", ") },
                        set: { draft.tags = commaSeparatedValues(from: $0) }
                    )
                )
                Picker("Intent", selection: $draft.intent) {
                    ForEach(SceneIntent.allCases) { intent in
                        Text(intent.title).tag(intent)
                    }
                }
                Picker("Parent", selection: Binding(
                    get: { draft.extends },
                    set: { draft.extends = $0 }
                )) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(availableScenes.filter { $0.id != draft.id }) { scene in
                        Text(scene.name).tag(Optional(scene.id))
                    }
                }
                Picker("Merge Policy", selection: $draft.mergePolicy) {
                    ForEach(SceneMergePolicy.allCases) { policy in
                        Text(policyTitle(policy)).tag(policy)
                    }
                }
                Stepper("Priority: \(draft.priority)", value: $draft.priority, in: 0...100)
                LabeledContent("Created By", value: draft.createdBy)
                LabeledContent("Updated", value: draft.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }

            Section("Module Overrides") {
                ForEach(Array(draft.moduleOverrides.enumerated()), id: \.element.id) { index, _ in
                    VStack(alignment: .leading) {
                        HStack {
                            Picker("Module", selection: $draft.moduleOverrides[index].moduleID) {
                                ForEach(SceneModuleID.allCases) { moduleID in
                                    Text(moduleID.title).tag(moduleID)
                                }
                            }
                            Button {
                                moveModuleOverride(from: index, offset: -1)
                            } label: {
                                Image(systemName: "arrow.up")
                            }
                            .disabled(index == 0)
                            Button {
                                moveModuleOverride(from: index, offset: 1)
                            } label: {
                                Image(systemName: "arrow.down")
                            }
                            .disabled(index == draft.moduleOverrides.count - 1)
                            Button(role: .destructive) {
                                draft.moduleOverrides.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        Picker("State", selection: $draft.moduleOverrides[index].state) {
                            ForEach(SceneModuleState.allCases) { state in
                                Text(state.rawValue).tag(state)
                            }
                        }
                        Picker("Visibility", selection: $draft.moduleOverrides[index].visibility) {
                            ForEach(SceneModuleVisibility.allCases) { visibility in
                                Text(visibility.rawValue).tag(visibility)
                            }
                        }
                        Stepper(
                            "Order: \(draft.moduleOverrides[index].panelOrder ?? 0)",
                            value: Binding(
                                get: { draft.moduleOverrides[index].panelOrder ?? 0 },
                                set: { draft.moduleOverrides[index].panelOrder = $0 }
                            ),
                            in: 0...20
                        )
                        ScenePinnedActionsEditor(
                            actions: $draft.moduleOverrides[index].pinnedActions,
                            supportedActions: moduleCapability(draft.moduleOverrides[index].moduleID)?.supportedActions ?? []
                        )
                        SceneSettingsEditor(
                            settings: $draft.moduleOverrides[index].settings,
                            supportedKeys: moduleCapability(draft.moduleOverrides[index].moduleID)?.configurableSettings ?? []
                        )
                        if let capability = moduleCapability(draft.moduleOverrides[index].moduleID) {
                            if !capability.configurableSettings.isEmpty {
                                Text("Supported Settings: \(capability.configurableSettings.joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if !capability.supportedActions.isEmpty {
                                Text("Supported Actions: \(capability.supportedActions.joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Button("Add Module Override") {
                    draft.moduleOverrides.append(SceneModuleOverride(moduleID: .flowInbox))
                }
            }

            Section("Triggers") {
                ForEach(Array(draft.triggers.enumerated()), id: \.element.id) { index, trigger in
                    VStack(alignment: .leading) {
                        HStack {
                            Picker("Type", selection: $draft.triggers[index].type) {
                                ForEach(SceneTriggerType.allCases) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            Button(role: .destructive) {
                                draft.triggers.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        TextField("Primary Match", text: $draft.triggers[index].match.primary)
                        TextField("Secondary Match", text: $draft.triggers[index].match.secondary)
                        TextField(
                            "Additional Values",
                            text: Binding(
                                get: { draft.triggers[index].match.values.joined(separator: ", ") },
                                set: { draft.triggers[index].match.values = commaSeparatedValues(from: $0) }
                            )
                        )
                        Stepper(
                            "Debounce: \(Int(draft.triggers[index].debounce ?? 0))s",
                            value: Binding(
                                get: { Int(draft.triggers[index].debounce ?? 0) },
                                set: { draft.triggers[index].debounce = $0 == 0 ? nil : TimeInterval($0) }
                            ),
                            in: 0...300
                        )
                        Stepper(
                            "Cooldown: \(Int(draft.triggers[index].cooldown ?? 0))s",
                            value: Binding(
                                get: { Int(draft.triggers[index].cooldown ?? 0) },
                                set: { draft.triggers[index].cooldown = $0 == 0 ? nil : TimeInterval($0) }
                            ),
                            in: 0...3600
                        )
                        Toggle("Enabled", isOn: $draft.triggers[index].enabled)
                    }
                }

                Button("Add Trigger") {
                    draft.triggers.append(SceneTrigger(type: .manual))
                }
            }

            SceneActionListEditor(title: "Enter Actions", actions: $draft.onEnter)
            SceneActionListEditor(title: "Exit Actions", actions: $draft.onExit)
            SceneActionListEditor(title: "Failure Actions", actions: $draft.onFail)
            SceneActionListEditor(title: "Post Activate Actions", actions: $draft.postActivate)

            Section("Behavior Rules") {
                Toggle("Screenshots to Inbox", isOn: $draft.behaviorRules.newScreenshotsGoToInbox)
                Toggle("Prefer Inbox Favorites", isOn: $draft.behaviorRules.preferInboxFavorites)
                Toggle("Prioritize Recent Content", isOn: $draft.behaviorRules.prioritizeRecentContent)
                TextField("Promoted Command Category", text: $draft.behaviorRules.promoteCommandPaletteCategory)
            }

            HStack {
                Button("Duplicate", action: onDuplicate)
                if !draft.isBuiltIn {
                    Button("Delete", role: .destructive, action: onDelete)
                }
                Spacer()
                Button("Preview") {
                    preview = makePreview(draft, availableScenes)
                    isShowingPreview = true
                }
                Button("Test") {
                    draft.updatedAt = Date()
                    onTest(draft)
                }
                Button("Save") {
                    draft.updatedAt = Date()
                    onSave(draft)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .sheet(isPresented: $isShowingPreview) {
            if let preview {
                ScenePreviewView(preview: preview)
            } else {
                Text("Preview unavailable")
                    .padding()
            }
        }
    }

    private func moveModuleOverride(from index: Int, offset: Int) {
        let target = index + offset
        guard draft.moduleOverrides.indices.contains(target) else { return }
        let item = draft.moduleOverrides.remove(at: index)
        draft.moduleOverrides.insert(item, at: target)
        for newIndex in draft.moduleOverrides.indices {
            draft.moduleOverrides[newIndex].panelOrder = newIndex
        }
    }

    private func commaSeparatedValues(from rawValue: String) -> [String] {
        rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func policyTitle(_ policy: SceneMergePolicy) -> String {
        switch policy {
        case .replace:
            return "Replace"
        case .append:
            return "Append"
        case .explicitDisable:
            return "Explicit Disable"
        }
    }
}

private struct ScenePreviewView: View {
    let preview: ScenePreview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Scene Preview", systemImage: preview.definition.icon)
                    .font(.headline)

                Text(preview.definition.name)
                    .font(.title3.weight(.semibold))
                Text("Intent: \(preview.definition.intent.title)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Merge Policy: \(preview.definition.mergePolicy.rawValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !preview.definition.tags.isEmpty {
                    Text("Tags: \(preview.definition.tags.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text("Created By: \(preview.definition.createdBy)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Updated: \(preview.definition.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Divider()

                Text("Triggers")
                    .font(.subheadline.weight(.semibold))
                if preview.triggerSummaries.isEmpty {
                    Text("No triggers configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(preview.triggerSummaries, id: \.self) { summary in
                        Text(summary)
                            .font(.caption)
                    }
                }

                Divider()

                Text("Effective Modules")
                    .font(.subheadline.weight(.semibold))
                ForEach(preview.resolved.moduleOverrides) { override in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(override.moduleID.title)
                            Spacer()
                            Text("\(override.visibility.rawValue) • \(override.state.rawValue)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let panelOrder = override.panelOrder {
                            Text("Panel Order: \(panelOrder)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if !override.pinnedActions.isEmpty {
                            Text("Pinned Actions: \(override.pinnedActions.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if !override.settings.isEmpty {
                            Text("Settings: \(override.settings.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if !preview.moduleSnapshots.isEmpty {
                    Divider()

                    Text("Module Capabilities")
                        .font(.subheadline.weight(.semibold))
                    ForEach(preview.moduleSnapshots) { snapshot in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(snapshot.moduleID.title)
                                Spacer()
                                Text(snapshot.isAvailable ? "Available" : "Unavailable")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(snapshot.isAvailable ? .green : .orange)
                            }
                            Text(snapshot.stateSummary)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if !snapshot.configurableSettings.isEmpty {
                                Text("Settings: \(snapshot.configurableSettings.joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if !snapshot.supportedActions.isEmpty {
                                Text("Actions: \(snapshot.supportedActions.joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                Divider()

                Text("Behavior Rules")
                    .font(.subheadline.weight(.semibold))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Screenshots to Inbox: \(preview.resolved.behaviorRules.newScreenshotsGoToInbox ? "On" : "Off")")
                    Text("Prefer Inbox Favorites: \(preview.resolved.behaviorRules.preferInboxFavorites ? "On" : "Off")")
                    Text("Prioritize Recent Content: \(preview.resolved.behaviorRules.prioritizeRecentContent ? "On" : "Off")")
                    if !preview.resolved.behaviorRules.promoteCommandPaletteCategory.isEmpty {
                        Text("Promoted Command Category: \(preview.resolved.behaviorRules.promoteCommandPaletteCategory)")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Divider()

                Text("Action Plan")
                    .font(.subheadline.weight(.semibold))
                ForEach(preview.actionPhases) { phase in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(phase.title)
                            .font(.caption.weight(.semibold))
                        if phase.actions.isEmpty {
                            Text("No actions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(phase.actions) { action in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(action.summary)
                                            .font(.caption)
                                        Spacer()
                                        SceneDryRunStatusLabel(status: action.status)
                                    }
                                    Text(action.detail)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()
        }
        .frame(minWidth: 520, minHeight: 520)
    }
}

private struct ScenePinnedActionsEditor: View {
    @Binding var actions: [String]
    let supportedActions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pinned Actions")
                .font(.caption.weight(.semibold))

            ForEach(Array(actions.indices), id: \.self) { index in
                HStack {
                    Picker("Action", selection: actionNameBinding(for: index)) {
                        ForEach(actionChoices(for: index), id: \.self) { actionName in
                            Text(actionName).tag(actionName)
                        }
                    }
                    TextField("Argument", text: actionArgumentBinding(for: index))
                    Button(role: .destructive) {
                        actions.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }

            Button("Add Pinned Action") {
                actions.append(defaultPinnedAction)
            }
            .font(.caption)
        }
    }

    private var defaultPinnedAction: String {
        supportedActions.first ?? "toggle-keep-awake"
    }

    private func actionChoices(for index: Int) -> [String] {
        let currentName = parsePinnedAction(actions[index]).name
        return Array(Set(supportedActions + [currentName])).sorted()
    }

    private func actionNameBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { parsePinnedAction(actions[index]).name },
            set: { newName in
                let parsed = parsePinnedAction(actions[index])
                actions[index] = buildPinnedAction(name: newName, argument: parsed.argument)
            }
        )
    }

    private func actionArgumentBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { parsePinnedAction(actions[index]).argument },
            set: { newArgument in
                let parsed = parsePinnedAction(actions[index])
                actions[index] = buildPinnedAction(name: parsed.name, argument: newArgument)
            }
        )
    }

    private func parsePinnedAction(_ rawValue: String) -> (name: String, argument: String) {
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        return (parts.first ?? rawValue, parts.count > 1 ? parts[1] : "")
    }

    private func buildPinnedAction(name: String, argument: String) -> String {
        let trimmedArgument = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedArgument.isEmpty else {
            return name
        }
        return "\(name):\(trimmedArgument)"
    }
}

private struct SceneSettingsEditor: View {
    @Binding var settings: [String: String]
    let supportedKeys: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.caption.weight(.semibold))

            ForEach(orderedKeys, id: \.self) { key in
                HStack {
                    Text(key)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 140, alignment: .leading)
                    TextField("Value", text: valueBinding(for: key))
                    Button(role: .destructive) {
                        settings.removeValue(forKey: key)
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }

            Menu("Add Setting") {
                if supportedKeys.isEmpty {
                    Button("Custom Setting") {
                        addSetting(named: nextCustomKey)
                    }
                } else {
                    ForEach(availableSettingChoices, id: \.self) { key in
                        Button(key) {
                            addSetting(named: key)
                        }
                    }
                    Button("Custom Setting") {
                        addSetting(named: nextCustomKey)
                    }
                }
            }
            .font(.caption)
        }
    }

    private var orderedKeys: [String] {
        settings.keys.sorted()
    }

    private var availableSettingChoices: [String] {
        let usedKeys = Set(settings.keys)
        let unused = supportedKeys.filter { usedKeys.contains($0) == false }
        return unused.isEmpty ? supportedKeys : unused
    }

    private var nextCustomKey: String {
        let base = "custom-setting"
        var suffix = 1
        while settings.keys.contains("\(base)-\(suffix)") {
            suffix += 1
        }
        return "\(base)-\(suffix)"
    }

    private func addSetting(named key: String) {
        settings[key] = settings[key] ?? ""
    }

    private func valueBinding(for key: String) -> Binding<String> {
        Binding(
            get: { settings[key] ?? "" },
            set: { settings[key] = $0 }
        )
    }
}

private struct SceneDryRunStatusLabel: View {
    let status: ScenePreview.DryRunStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .ready:
            return .green
        case .attention:
            return .orange
        case .unavailable:
            return .red
        }
    }
}

private struct SceneActionListEditor: View {
    let title: String
    @Binding var actions: [SceneAction]

    var body: some View {
        Section(title) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, _ in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Title", text: $actions[index].title)
                        Button(role: .destructive) {
                            actions.remove(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    Picker("Type", selection: $actions[index].type) {
                        ForEach(SceneActionType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    Picker("Failure Policy", selection: $actions[index].failurePolicy) {
                        ForEach(SceneActionFailurePolicy.allCases) { policy in
                            Text(policy.rawValue).tag(policy)
                        }
                    }
                    Picker("Retry Policy", selection: $actions[index].retryPolicy) {
                        ForEach(SceneActionRetryPolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    TextField(
                        "Primary Param",
                        text: Binding(
                            get: { actions[index].params["name"] ?? actions[index].params["title"] ?? actions[index].params["target"] ?? "" },
                            set: { actions[index].params["name"] = $0 }
                        )
                    )
                    Stepper(
                        "Timeout: \(Int(actions[index].timeout))s",
                        value: $actions[index].timeout,
                        in: 1...120,
                        step: 1
                    )
                }
            }

            Button("Add Action") {
                actions.append(
                    SceneAction(
                        title: "New Action",
                        type: .atlasAction,
                        params: ["name": "toggle-keep-awake"]
                    )
                )
            }
        }
    }
}

private struct SceneRecordStatusLabel: View {
    let status: SceneExecutionRecord.Status

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor.opacity(0.14))
            .foregroundColor(backgroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch status {
        case .success:
            return .green
        case .failed:
            return .red
        case .skipped:
            return .orange
        }
    }
}

struct SceneCommandProvider: CommandProviding {
    let coordinator: SceneCoordinator
    let isEnabled: () -> Bool

    func results(for query: String) -> [PaletteCommand] {
        guard isEnabled() else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sceneCommands = coordinator.scenes.map { scene in
            PaletteCommand(
                id: scene.id,
                title: "Switch to \(scene.name)",
                subtitle: "Activate \(scene.intent.title.lowercased()) scene",
                icon: .sfSymbol(scene.icon),
                keywords: ["scene", "switch", scene.name.lowercased(), scene.intent.rawValue],
                action: .execute {
                    coordinator.activateScene(id: scene.id, reason: "Command palette", isManual: true)
                },
                category: "Scenes"
            )
        }

        let staticCommands = [
            PaletteCommand(
                id: UUID(),
                title: "Scene Editor",
                subtitle: "Create and customize scenes",
                icon: .sfSymbol("slider.horizontal.3"),
                keywords: ["scene", "editor", "automation"],
                action: .push(.sceneEditor),
                category: "Scenes"
            ),
            PaletteCommand(
                id: UUID(),
                title: "Scene Diagnostics",
                subtitle: "See why a scene is active",
                icon: .sfSymbol("stethoscope"),
                keywords: ["scene", "diagnostics", "debug"],
                action: .push(.sceneDiagnostics),
                category: "Scenes"
            ),
        ]

        let commands = staticCommands + sceneCommands
        guard !trimmed.isEmpty else {
            return commands
        }

        return commands.filter { command in
            command.title.lowercased().contains(trimmed)
                || command.subtitle?.lowercased().contains(trimmed) == true
                || command.keywords.contains(where: { $0.contains(trimmed) })
        }
    }
}

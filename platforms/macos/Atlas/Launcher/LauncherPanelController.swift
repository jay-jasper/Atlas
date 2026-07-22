import AppKit
import SwiftUI

private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Hosts the launcher UI in a floating NSPanel. Replaces CommandPaletteController.
@MainActor
final class LauncherPanelController {
    private var panel: NSPanel?
    private var mouseMonitor: Any?
    private var keyMonitor: Any?

    private let sources: [LauncherItemSource]
    private let usageRecorder: CommandUsageRecording
    let styleStore: LauncherStyleStore
    let favorites: FavoritesStore
    private let nav = LauncherNavigationModel()
    private let automationRunner: AutomationProcessRunning

    // Optional stores wired in later phases.
    var fallbackItemsProvider: ((String) -> [LauncherItem])?
    var aliasResolver: AliasResolving?

    // Injected closure builders for legacy sub-views (same contract as the old palette).
    var screenshotLibraryViewBuilder: (() -> AnyView)?
    var portLookupViewBuilder: (() -> AnyView)?
    var windowPickerViewBuilder: (() -> AnyView)?
    var workspaceViewBuilder: (() -> AnyView)?
    var tokenBarViewBuilder: (() -> AnyView)?
    var audioHubViewBuilder: (() -> AnyView)?
    var flowInboxViewBuilder: (() -> AnyView)?
    var textToolboxViewBuilder: (() -> AnyView)?
    var sceneEditorViewBuilder: (() -> AnyView)?
    var sceneDiagnosticsViewBuilder: (() -> AnyView)?
    var scratchpadViewBuilder: ((UUID?) -> AnyView)?
    var skillRunViewBuilder: ((SkillDefinition) -> AnyView)?

    var onHotkeyChanged: ((HotkeyConfig) -> Void)?

    init(
        sources: [LauncherItemSource],
        usageRecorder: CommandUsageRecording = CommandUsageStore(),
        styleStore: LauncherStyleStore,
        favorites: FavoritesStore,
        automationRunner: AutomationProcessRunning = SystemAutomationProcessRunner()
    ) {
        self.sources = sources
        self.usageRecorder = usageRecorder
        self.styleStore = styleStore
        self.favorites = favorites
        self.automationRunner = automationRunner
    }

    deinit {
        let monitors = [mouseMonitor, keyMonitor].compactMap { $0 }
        if !monitors.isEmpty {
            DispatchQueue.main.async {
                monitors.forEach { NSEvent.removeMonitor($0) }
            }
        }
    }

    func updateHotkey(_ config: HotkeyConfig) {
        onHotkeyChanged?(config)
    }

    // MARK: Visibility

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard panel == nil || panel?.isVisible == false else { return }
        removeMonitors()
        nav.resetToRoot()

        let style = styleStore.style.sanitized()
        let rootView = LauncherRootView(
            nav: nav,
            styleStore: styleStore,
            buildSections: { [weak self] query in self?.buildSections(query: query) ?? [] },
            legacyViewBuilder: { [weak self] destination in
                self?.legacyView(for: destination) ?? AnyView(Text("Unavailable").padding())
            },
            onOutcome: { [weak self] item, outcome in self?.handle(item: item, outcome: outcome) },
            onDismiss: { [weak self] in
                Task { @MainActor [weak self] in self?.hide() }
            }
        )

        let panelWidth = style.panelWidth
        let panelHeight: CGFloat = 52 + CGFloat(style.maxVisibleRows) * style.rowHeight + 20 + 40 + 2
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = CGRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        let newPanel = LauncherPanel(
            contentRect: CGRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .modalPanel
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = false
        newPanel.contentView = hostingView
        newPanel.isReleasedWhenClosed = false

        position(newPanel, topOffsetRatio: style.topOffsetRatio)
        newPanel.makeKeyAndOrderFront(nil)
        newPanel.orderFrontRegardless()
        panel = newPanel

        installMonitors()
    }

    func hide() {
        panel?.close()
        panel = nil
        removeMonitors()
        nav.resetToRoot()
    }

    // MARK: Section building

    private func buildSections(query: String) -> [LauncherSectionData] {
        LauncherSectionBuilder.build(
            query: query,
            sources: sources,
            favorites: favorites.pinnedKeys,
            records: usageRecorder.usageRecords(),
            fallbackItems: fallbackItemsProvider?(query) ?? [],
            aliases: aliasResolver
        )
    }

    private func selectedRootItem() -> LauncherItem? {
        guard nav.stack.isEmpty else { return nil }
        let flattened = buildSections(query: nav.query).flatMap(\.items)
        return flattened.indices.contains(nav.selectedIndex) ? flattened[nav.selectedIndex] : nil
    }

    // MARK: Outcome handling

    func handle(item: LauncherItem, outcome: LauncherActionOutcome) {
        usageRecorder.recordUsage(commandKey: item.id)
        switch outcome {
        case .dismiss:
            hide()
        case .stay:
            break
        case .push(let page):
            nav.push(page)
        }
    }

    /// Execute an item directly (used by per-command hotkeys). `.push` opens the panel on the page.
    func execute(commandKey: String) {
        let rootItems = sources.flatMap { $0.items(for: "") }
        guard let item = rootItems.first(where: { $0.id == commandKey }),
              let primary = item.primaryAction else { return }
        usageRecorder.recordUsage(commandKey: item.id)
        switch primary.perform() {
        case .dismiss, .stay:
            break
        case .push(let page):
            show()
            nav.push(page)
        }
    }

    // MARK: Legacy destinations

    private func legacyView(for destination: PaletteDestination) -> AnyView {
        switch destination {
        case .screenshotLibrary:
            return screenshotLibraryViewBuilder?() ?? AnyView(Text("Screenshot Library").padding())
        case .portLookup:
            return portLookupViewBuilder?() ?? AnyView(Text("Port Lookup").padding())
        case .windowPicker:
            return windowPickerViewBuilder?() ?? AnyView(Text("Window Picker").padding())
        case .workspaces:
            return workspaceViewBuilder?() ?? AnyView(Text("Workspaces").padding())
        case .tokenBar:
            return tokenBarViewBuilder?() ?? AnyView(Text("TokenBar").padding())
        case .audioHub:
            return audioHubViewBuilder?() ?? AnyView(Text("Audio Hub").padding())
        case .flowInbox:
            return flowInboxViewBuilder?() ?? AnyView(Text("Flow Inbox").padding())
        case .textToolbox:
            return textToolboxViewBuilder?() ?? AnyView(Text("Text Toolbox").padding())
        case .sceneEditor:
            return sceneEditorViewBuilder?() ?? AnyView(Text("Scene Editor").padding())
        case .sceneDiagnostics:
            return sceneDiagnosticsViewBuilder?() ?? AnyView(Text("Scene Diagnostics").padding())
        case .scratchpad(let noteID):
            return scratchpadViewBuilder?(noteID) ?? AnyView(Text("Scratchpad").padding())
        case .automationOutput(let command):
            return AnyView(AutomationOutputView(command: command, runner: automationRunner))
        case .skillRun(let skill):
            return skillRunViewBuilder?(skill) ?? AnyView(Text(skill.title).padding())
        }
    }

    // MARK: Monitors

    private func installMonitors() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let panel = self.panel else { return }
                if !panel.frame.contains(NSEvent.mouseLocation) {
                    self.hide()
                }
            }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isVisible == true else { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // ⌘K toggles the action panel.
            if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "k" {
                self.nav.isActionPanelOpen.toggle()
                return nil
            }

            // ⌘↵ runs the second action of the selected root item.
            if flags == .command, event.keyCode == 36 || event.keyCode == 76 {
                if let item = self.selectedRootItem(), item.actions.count > 1 {
                    self.handle(item: item, outcome: item.actions[1].perform())
                }
                return nil
            }

            // ⌃N / ⌃P → substitute down / up arrow events (vim-style navigation).
            if flags == .control, let char = event.charactersIgnoringModifiers?.lowercased(),
               char == "n" || char == "p" {
                let keyCode: UInt16 = char == "n" ? 125 : 126
                return NSEvent.keyEvent(
                    with: .keyDown,
                    location: event.locationInWindow,
                    modifierFlags: [],
                    timestamp: event.timestamp,
                    windowNumber: event.windowNumber,
                    context: nil,
                    characters: "",
                    charactersIgnoringModifiers: "",
                    isARepeat: event.isARepeat,
                    keyCode: keyCode
                ) ?? event
            }

            return event
        }
    }

    private func removeMonitors() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        mouseMonitor = nil
        keyMonitor = nil
    }

    private func position(_ panel: NSPanel, topOffsetRatio: Double) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - panel.frame.width / 2
        let y = screenFrame.maxY - screenFrame.height * topOffsetRatio - panel.frame.height
        panel.setFrameOrigin(CGPoint(x: x, y: max(y, screenFrame.minY)))
    }
}

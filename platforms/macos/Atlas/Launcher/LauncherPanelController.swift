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
    private var flagsMonitor: Any?
    private var resizeObserver: NSObjectProtocol?

    private let sources: [LauncherItemSource]
    private let usageRecorder: CommandUsageRecording
    let styleStore: LauncherStyleStore
    let favorites: FavoritesStore
    private let nav = LauncherNavigationModel()
    private let automationRunner: AutomationProcessRunning

    // Optional stores wired in later phases.
    var fallbackItemsProvider: ((String) -> [LauncherItem])?
    var aliasResolver: AliasResolving?

    /// 搜索总控(懒建:等 alias/fallback 接线完成后第一次 show 时创建)。
    private(set) lazy var searchCoordinator = LauncherSearchCoordinator(
        sources: sources,
        favorites: { [weak self] in self?.favorites.pinnedKeys ?? [] },
        records: { [weak self] in self?.usageRecorder.usageRecords() ?? [:] },
        fallbackItems: { [weak self] query in self?.fallbackItemsProvider?(query) ?? [] },
        aliases: aliasResolver,
        aliasName: { [weak self] key in
            (self?.aliasResolver as? AliasStore)?.alias(for: key)
        }
    )

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
        // 以面板存在性判断:再次按热键必定关闭,不依赖 isVisible 的时序。
        if panel != nil {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard panel == nil else { return }
        removeMonitors()
        nav.resetToRoot()

        let style = styleStore.style.sanitized()
        searchCoordinator.updateQuery("")
        let rootView = LauncherRootView(
            nav: nav,
            styleStore: styleStore,
            coordinator: searchCoordinator,
            legacyViewBuilder: { [weak self] destination in
                self?.legacyView(for: destination) ?? AnyView(Text("Unavailable").padding())
            },
            onOutcome: { [weak self] item, outcome in self?.handle(item: item, outcome: outcome) },
            onDismiss: { [weak self] in
                Task { @MainActor [weak self] in self?.hide() }
            }
        )

        let panelWidth = style.panelWidth
        let defaultHeight: CGFloat = 64 + CGFloat(style.maxVisibleRows) * style.rowHeight + 20 + 40 + 2
        // 上次拖拽保存的高度优先(夹在上下限内)。
        let savedHeight = UserDefaults.standard.double(forKey: "launcher.panel.height")
        let panelHeight = savedHeight > 0 ? min(max(savedHeight, 220), 900) : defaultHeight
        // 顶对齐 + 尾部 Spacer:空闲态只渲染搜索条,面板剩余区域保持透明。
        let hostingView = NSHostingView(rootView: VStack(spacing: 0) {
            rootView
            Spacer(minLength: 0)
        })
        hostingView.frame = CGRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        let newPanel = LauncherPanel(
            contentRect: CGRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        // 可拖边缘调整大小,限制最小/最大。
        newPanel.minSize = NSSize(width: 480, height: 220)
        newPanel.maxSize = NSSize(width: 960, height: 900)
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

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: newPanel,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self, let window = notification.object as? NSWindow else { return }
                let size = window.frame.size
                UserDefaults.standard.set(Double(size.height), forKey: "launcher.panel.height")
                let clampedWidth = min(max(size.width, 480), 960)
                if abs(self.styleStore.style.panelWidth - clampedWidth) > 1 {
                    self.styleStore.style.panelWidth = clampedWidth
                }
            }
        }

        installMonitors()
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self, self.panel?.isVisible == true else { return event }
            let holdingCommand = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask) == .command
            if self.nav.showIndexBadges != holdingCommand {
                self.nav.showIndexBadges = holdingCommand
            }
            return event
        }
    }

    func hide() {
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
        }
        resizeObserver = nil
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
        let flattened = searchCoordinator.sections.flatMap(\.items)
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

    /// All items available at the root (empty query) — used by the settings alias/hotkey editor.
    func allRootItems() -> [LauncherItem] {
        sources.flatMap { $0.items(for: "") }
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

            // ⌘, 关闭面板并打开主界面(设置在通用 tab)。
            if flags == .command, event.charactersIgnoringModifiers == "," {
                self.hide()
                AtlasServices.shared.openMainWindow?()
                return nil
            }

            // ⌘1-⌘9 直达第 N 条。
            if flags == .command,
               let char = event.charactersIgnoringModifiers,
               let digit = Int(char), (1...9).contains(digit) {
                let flattened = self.searchCoordinator.sections.flatMap(\.items)
                if flattened.indices.contains(digit - 1) {
                    let item = flattened[digit - 1]
                    if let primary = item.primaryAction {
                        self.handle(item: item, outcome: primary.perform())
                    }
                }
                return nil
            }

            // PageDown(121)/PageUp(116):按可见行数翻页。
            if event.keyCode == 121 || event.keyCode == 116 {
                let flattened = self.searchCoordinator.sections.flatMap(\.items)
                guard !flattened.isEmpty else { return nil }
                let page = self.styleStore.style.sanitized().maxVisibleRows
                let delta = event.keyCode == 121 ? page : -page
                self.nav.selectedIndex = min(max(self.nav.selectedIndex + delta, 0), flattened.count - 1)
                return nil
            }

            // ⌘↑ / ⌘↓:跳上/下一个分区首行。
            if flags == .command, event.keyCode == 126 || event.keyCode == 125 {
                let sections = self.searchCoordinator.sections
                guard !sections.isEmpty else { return nil }
                var starts: [Int] = []
                var offset = 0
                for section in sections {
                    starts.append(offset)
                    offset += section.items.count
                }
                let current = self.nav.selectedIndex
                if event.keyCode == 125 {
                    if let next = starts.first(where: { $0 > current }) {
                        self.nav.selectedIndex = next
                    }
                } else {
                    if let previous = starts.last(where: { $0 < current }) {
                        self.nav.selectedIndex = previous
                    }
                }
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
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        mouseMonitor = nil
        keyMonitor = nil
        flagsMonitor = nil
    }

    private func position(_ panel: NSPanel, topOffsetRatio: Double) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - panel.frame.width / 2
        let y = screenFrame.maxY - screenFrame.height * topOffsetRatio - panel.frame.height
        panel.setFrameOrigin(CGPoint(x: x, y: max(y, screenFrame.minY)))
    }
}

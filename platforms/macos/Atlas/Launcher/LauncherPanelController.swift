import AppKit
import Combine
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
    private var presentationObserver: AnyCancellable?
    private var expandedPanelHeight: CGFloat = 560

    private static let collapsedPanelHeight: CGFloat = 64
    private static let minimumExpandedPanelHeight: CGFloat = 220
    private static let maximumExpandedPanelHeight: CGFloat = 900
    private static let expandedHeightPreferenceKey = "launcher.panel.expanded-height.v2"

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

        presentationObserver = Publishers.CombineLatest(nav.$query, nav.$stack)
            .map { query, stack in
                stack.isEmpty && query.trimmingCharacters(in: .whitespaces).isEmpty
            }
            .removeDuplicates()
            .sink { [weak self] isRootIdle in
                self?.updatePanelPresentation(isRootIdle: isRootIdle)
            }
    }

    deinit {
        let monitors = [mouseMonitor, keyMonitor, flagsMonitor].compactMap { $0 }
        monitors.forEach { NSEvent.removeMonitor($0) }
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
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
        guard panel?.isVisible != true else { return }
        removeMonitors()
        nav.resetToRoot()

        let style = styleStore.style.sanitized()
        searchCoordinator.updateQuery("")
        let panelWidth = style.panelWidth
        let defaultHeight: CGFloat = 64 + CGFloat(style.maxVisibleRows) * style.rowHeight + 20 + 40 + 2
        // 上次拖拽保存的高度优先(夹在上下限内)。
        let savedHeight = UserDefaults.standard.double(forKey: Self.expandedHeightPreferenceKey)
        expandedPanelHeight = savedHeight > 0
            ? min(max(savedHeight, Self.minimumExpandedPanelHeight), Self.maximumExpandedPanelHeight)
            : defaultHeight
        let panelHeight = Self.collapsedPanelHeight

        let currentPanel: NSPanel
        if let panel {
            currentPanel = panel
            currentPanel.setContentSize(NSSize(width: panelWidth, height: panelHeight))
        } else {
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

            let hostingView = NSHostingView(rootView: rootView)
            hostingView.frame = CGRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

            let newPanel = LauncherPanel(
                contentRect: CGRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
                styleMask: [.borderless, .nonactivatingPanel, .resizable],
                backing: .buffered,
                defer: false
            )
            newPanel.minSize = NSSize(width: 480, height: Self.collapsedPanelHeight)
            newPanel.maxSize = NSSize(width: 960, height: Self.collapsedPanelHeight)
            newPanel.level = .modalPanel
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            newPanel.backgroundColor = .clear
            newPanel.isOpaque = false
            newPanel.hasShadow = false
            newPanel.contentView = hostingView
            newPanel.isReleasedWhenClosed = false
            panel = newPanel
            currentPanel = newPanel

            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didEndLiveResizeNotification,
                object: newPanel,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor [weak self] in
                    guard let self, let window = notification.object as? NSWindow else { return }
                    let size = window.frame.size
                    if size.height > Self.collapsedPanelHeight + 1 {
                        self.expandedPanelHeight = min(
                            max(size.height, Self.minimumExpandedPanelHeight),
                            Self.maximumExpandedPanelHeight
                        )
                        UserDefaults.standard.set(
                            Double(self.expandedPanelHeight),
                            forKey: Self.expandedHeightPreferenceKey
                        )
                    }
                    let clampedWidth = min(max(size.width, 480), 960)
                    if abs(self.styleStore.style.panelWidth - clampedWidth) > 1 {
                        self.styleStore.style.panelWidth = clampedWidth
                    }
                }
            }
        }

        position(currentPanel, topOffsetRatio: style.topOffsetRatio)
        currentPanel.contentView?.layoutSubtreeIfNeeded()
        currentPanel.displayIfNeeded()
        currentPanel.orderFrontRegardless()
        currentPanel.makeKey()

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

    private func updatePanelPresentation(isRootIdle: Bool) {
        guard let panel else { return }

        let targetHeight = isRootIdle ? Self.collapsedPanelHeight : expandedPanelHeight
        panel.minSize = NSSize(
            width: 480,
            height: isRootIdle ? Self.collapsedPanelHeight : Self.minimumExpandedPanelHeight
        )
        panel.maxSize = NSSize(
            width: 960,
            height: isRootIdle ? Self.collapsedPanelHeight : Self.maximumExpandedPanelHeight
        )

        guard abs(panel.frame.height - targetHeight) > 0.5 else { return }

        var frame = panel.frame
        let topEdge = frame.maxY
        frame.size.height = targetHeight
        frame.origin.y = topEdge - targetHeight
        if let screen = panel.screen ?? NSScreen.main {
            frame.origin.y = max(frame.origin.y, screen.visibleFrame.minY)
        }
        panel.setFrame(frame, display: true, animate: panel.isVisible)
    }

    func hide() {
        panel?.orderOut(nil)
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

    private struct SelectionContext {
        let items: [LauncherItem]
        let verticalStep: Int
        let supportsHorizontalNavigation: Bool
    }

    private func selectionContext() -> SelectionContext {
        guard let page = nav.currentPage else {
            return SelectionContext(
                items: searchCoordinator.sections.flatMap(\.items),
                verticalStep: 1,
                supportsHorizontalNavigation: false
            )
        }

        switch page {
        case .list(_, let items):
            return SelectionContext(
                items: LauncherPageView.filter(items(), query: nav.query),
                verticalStep: 1,
                supportsHorizontalNavigation: false
            )
        case .grid(_, let columns, let items):
            return SelectionContext(
                items: LauncherPageView.filter(items(), query: nav.query),
                verticalStep: max(columns, 1),
                supportsHorizontalNavigation: true
            )
        case .detail, .legacy:
            return SelectionContext(items: [], verticalStep: 1, supportsHorizontalNavigation: false)
        }
    }

    private func selectedItem() -> LauncherItem? {
        let items = selectionContext().items
        return items.indices.contains(nav.selectedIndex) ? items[nav.selectedIndex] : nil
    }

    private func runSelectedItem() {
        guard let item = selectedItem(), let primary = item.primaryAction else { return }
        handle(item: item, outcome: primary.perform())
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

            let flags = event.modifierFlags
                .intersection([.command, .option, .control, .shift])

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
                let context = self.selectionContext()
                guard !context.items.isEmpty else { return nil }
                let page = self.styleStore.style.sanitized().maxVisibleRows
                let delta = event.keyCode == 121 ? page : -page
                self.nav.moveSelection(by: delta, itemCount: context.items.count)
                return nil
            }

            // ⌘↑ / ⌘↓:跳上/下一个分区首行。
            if self.nav.stack.isEmpty,
               flags == .command,
               event.keyCode == 126 || event.keyCode == 125 {
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
                if let item = self.selectedItem(), item.actions.count > 1 {
                    self.handle(item: item, outcome: item.actions[1].perform())
                }
                return nil
            }

            // ⌃N / ⌃P:vim-style navigation.
            if flags == .control, let char = event.charactersIgnoringModifiers?.lowercased(),
               char == "n" || char == "p" {
                let context = self.selectionContext()
                let delta = char == "n" ? context.verticalStep : -context.verticalStep
                self.nav.moveSelection(by: delta, itemCount: context.items.count)
                return nil
            }

            // Search field keeps focus for typing; navigation is handled before
            // NSTextField consumes arrow/return/escape events.
            if flags.isEmpty, !self.nav.isActionPanelOpen {
                let context = self.selectionContext()
                switch event.keyCode {
                case 126:
                    self.nav.moveSelection(by: -context.verticalStep, itemCount: context.items.count)
                    return nil
                case 125:
                    self.nav.moveSelection(by: context.verticalStep, itemCount: context.items.count)
                    return nil
                case 123 where context.supportsHorizontalNavigation:
                    self.nav.moveSelection(by: -1, itemCount: context.items.count)
                    return nil
                case 124 where context.supportsHorizontalNavigation:
                    self.nav.moveSelection(by: 1, itemCount: context.items.count)
                    return nil
                case 36, 76:
                    self.runSelectedItem()
                    return nil
                case 53:
                    if !self.nav.popOrSignalDismiss() {
                        self.hide()
                    }
                    return nil
                default:
                    break
                }
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

import AppKit
import SwiftUI

/// Root launcher UI: search field, sectioned results (or pushed page), footer bar, ⌘K overlay.
struct LauncherRootView: View {
    @ObservedObject var nav: LauncherNavigationModel
    @ObservedObject var styleStore: LauncherStyleStore
    let buildSections: (String) -> [LauncherSectionData]
    let legacyViewBuilder: (PaletteDestination) -> AnyView
    let onOutcome: (LauncherItem, LauncherActionOutcome) -> Void
    let onDismiss: () -> Void

    private var style: LauncherStyle { styleStore.style.sanitized() }
    private var accent: Color { style.accent?.color ?? Color.accentColor }

    @AppStorage("atlas.shell.theme") private var shellThemeRaw = ShellThemeKind.plain.rawValue

    private var shellTheme: ShellThemeKind {
        ShellThemeKind(rawValue: shellThemeRaw) ?? .plain
    }

    private var systemColorScheme: ColorScheme {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    private struct FlatRow: Identifiable {
        let id: String
        let item: LauncherItem
        let sectionTitle: String?   // set on the first row of a section
        let isAnswer: Bool
    }

    private func flattenedRows(_ sections: [LauncherSectionData]) -> [FlatRow] {
        var rows: [FlatRow] = []
        for section in sections {
            for (index, item) in section.items.enumerated() {
                let header = index == 0 && !section.title.isEmpty ? section.title : nil
                rows.append(FlatRow(
                    id: "\(section.title)#\(item.id)",
                    item: item,
                    sectionTitle: header,
                    isAnswer: section.id == .answer
                ))
            }
        }
        return rows
    }

    var body: some View {
        // 默认只显示搜索框:空查询不出结果列表,输入后才展开。
        let isRootIdle = nav.stack.isEmpty
            && nav.query.trimmingCharacters(in: .whitespaces).isEmpty
        let sections = (nav.stack.isEmpty && !isRootIdle) ? buildSections(nav.query) : []
        let rows = flattenedRows(sections)
        let selected: LauncherItem? = {
            if nav.stack.isEmpty {
                return rows.indices.contains(nav.selectedIndex) ? rows[nav.selectedIndex].item : nil
            }
            return pageSelectedItem()
        }()

        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                searchBar

                if !isRootIdle {
                    Divider().opacity(0.4)
                }

                if isRootIdle {
                    EmptyView()
                } else if nav.stack.isEmpty {
                    rootList(rows: rows, selected: selected)
                } else if let page = nav.currentPage {
                    LauncherPageView(
                        page: page,
                        nav: nav,
                        style: style,
                        accent: accent,
                        legacyViewBuilder: legacyViewBuilder,
                        onOutcome: onOutcome
                    )
                    .frame(maxHeight: CGFloat(style.maxVisibleRows) * style.rowHeight + 20)
                }

                if !isRootIdle {
                    Divider().opacity(0.4)
                    footerBar(selected: selected)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: .infinity, alignment: .top)

            if nav.isActionPanelOpen, let selected, !selected.actions.isEmpty {
                ActionPanelView(
                    actions: selected.actions,
                    fontSize: style.fontSize,
                    accent: accent,
                    onRun: { action in
                        nav.isActionPanelOpen = false
                        onOutcome(selected, action.perform())
                    },
                    onClose: { nav.isActionPanelOpen = false }
                )
                .padding(.bottom, 40)
            }
        }
        .noDefaultFocus()
        .environment(\.shellThemeKind, shellTheme)
        .environment(\.colorScheme, shellTheme.spec.colorScheme ?? systemColorScheme)
        .background(backgroundView)
        .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .stroke(style.borderColor.color, lineWidth: style.borderWidth)
        )
        .shadow(radius: 16, y: 6)
        .onKeyPressCompatible(.escape) {
            if !nav.popOrSignalDismiss() {
                onDismiss()
            }
            return .handled
        }
    }

    // MARK: Background

    @ViewBuilder
    private var backgroundView: some View {
        switch style.background {
        case .theme:
            shellTheme.spec.makeBackground()
        case .material(let opacity):
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color(nsColor: .windowBackgroundColor).opacity(1 - opacity)
            }
        case .solid(let color):
            color.color
        case .gradient(let from, let to, let angleDegrees):
            LinearGradient(
                colors: [from.color, to.color],
                startPoint: startPoint(for: angleDegrees),
                endPoint: endPoint(for: angleDegrees)
            )
        }
    }

    private func startPoint(for angle: Double) -> UnitPoint {
        let radians = angle * .pi / 180
        return UnitPoint(x: 0.5 - cos(radians) / 2, y: 0.5 - sin(radians) / 2)
    }

    private func endPoint(for angle: Double) -> UnitPoint {
        let radians = angle * .pi / 180
        return UnitPoint(x: 0.5 + cos(radians) / 2, y: 0.5 + sin(radians) / 2)
    }

    // MARK: Search bar

    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: 8) {
            if !nav.stack.isEmpty {
                Button {
                    _ = nav.popOrSignalDismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            } else {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
            }
            TextField(nav.stack.isEmpty ? "Search Atlas…" : "Filter…", text: $nav.query)
                .textFieldStyle(.plain)
                .font(.system(size: style.fontSize + 3))
                .onChange(of: nav.query) { _ in nav.selectedIndex = 0 }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    // MARK: Root list

    @ViewBuilder
    private func rootList(rows: [FlatRow], selected: LauncherItem?) -> some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            VStack(spacing: 0) {
                                if let header = row.sectionTitle {
                                    LauncherSectionHeader(title: header, fontSize: style.fontSize)
                                }
                                if row.isAnswer {
                                    LauncherAnswerCard(
                                        item: row.item,
                                        isSelected: index == nav.selectedIndex,
                                        style: style,
                                        accent: accent
                                    )
                                    .onTapGesture { runPrimary(row.item) }
                                } else {
                                    LauncherResultRow(
                                        item: row.item,
                                        isSelected: index == nav.selectedIndex,
                                        style: style,
                                        accent: accent
                                    )
                                    .onTapGesture { runPrimary(row.item) }
                                }
                            }
                            .id(index)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: CGFloat(style.maxVisibleRows) * style.rowHeight + 20)
                .onKeyPressCompatible(.upArrow) {
                    moveSelection(-1, count: rows.count, proxy: proxy)
                    return .handled
                }
                .onKeyPressCompatible(.downArrow) {
                    moveSelection(1, count: rows.count, proxy: proxy)
                    return .handled
                }
                .onKeyPressCompatible(.return) {
                    if let selected { runPrimary(selected) }
                    return .handled
                }
                .onKeyPressCompatible(.tab) {
                    if let selected { runPrimary(selected) }
                    return .handled
                }
            }
            .frame(maxWidth: .infinity)

            if let detail = selected?.detail {
                Divider()
                LauncherDetailPane(detail: detail, style: style)
                    .frame(width: 260)
            }
        }
    }

    private func moveSelection(_ delta: Int, count: Int, proxy: ScrollViewProxy) {
        let next = nav.selectedIndex + delta
        guard next >= 0, next < count else { return }
        nav.selectedIndex = next
        proxy.scrollTo(next, anchor: .center)
    }

    private func runPrimary(_ item: LauncherItem) {
        guard let primary = item.primaryAction else { return }
        onOutcome(item, primary.perform())
    }

    private func pageSelectedItem() -> LauncherItem? {
        guard let page = nav.currentPage else { return nil }
        switch page {
        case .list(_, let items), .grid(_, _, let items):
            let filtered = LauncherPageView.filter(items(), query: nav.query)
            return filtered.indices.contains(nav.selectedIndex) ? filtered[nav.selectedIndex] : nil
        case .detail, .legacy:
            return nil
        }
    }

    // MARK: Footer

    @ViewBuilder
    private func footerBar(selected: LauncherItem?) -> some View {
        HStack(spacing: 10) {
            if let selected {
                LauncherIconView(icon: selected.icon, size: 20, accent: accent)
                Text(selected.title)
                    .font(.system(size: style.fontSize - 2))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Image(systemName: "sparkle")
                    .foregroundColor(.secondary)
                Text("Atlas")
                    .font(.system(size: style.fontSize - 2))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let primary = selected?.primaryAction {
                HStack(spacing: 4) {
                    Text(primary.title)
                        .font(.system(size: style.fontSize - 2))
                    Text("↵")
                        .font(.system(size: style.fontSize - 2))
                        .foregroundColor(.secondary)
                }
            }

            if let selected, selected.actions.count > 1 {
                Divider().frame(height: 14)
                Button {
                    nav.isActionPanelOpen.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text("Actions")
                            .font(.system(size: style.fontSize - 2))
                        Text("⌘K")
                            .font(.system(size: style.fontSize - 3))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }
}

import SwiftUI

/// Renders a pushed LauncherPage (list / grid / detail / legacy bridge).
struct LauncherPageView: View {
    let page: LauncherPage
    @ObservedObject var nav: LauncherNavigationModel
    let style: LauncherStyle
    let accent: Color
    let legacyViewBuilder: (PaletteDestination) -> AnyView
    let onOutcome: (LauncherItem, LauncherActionOutcome) -> Void

    static func filter(_ items: [LauncherItem], query: String) -> [LauncherItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        return items.filter { item in
            item.title.localizedCaseInsensitiveContains(trimmed)
                || item.keywords.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    var body: some View {
        switch page {
        case .list(_, let items):
            listBody(Self.filter(items(), query: nav.query))
        case .grid(_, let columns, let items):
            gridBody(Self.filter(items(), query: nav.query), columns: columns)
        case .detail(_, let detail):
            LauncherDetailPane(detail: detail, style: style)
        case .legacy(let destination):
            legacyViewBuilder(destination)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: List page

    @ViewBuilder
    private func listBody(_ items: [LauncherItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        LauncherResultRow(
                            item: item,
                            isSelected: index == nav.selectedIndex,
                            style: style,
                            accent: accent
                        )
                        .id(index)
                        .onTapGesture { run(item) }
                    }
                }
                .padding(.vertical, 4)
            }
            .onKeyPressCompatible(.upArrow) {
                move(-1, count: items.count, proxy: proxy)
                return .handled
            }
            .onKeyPressCompatible(.downArrow) {
                move(1, count: items.count, proxy: proxy)
                return .handled
            }
            .onKeyPressCompatible(.return) {
                if items.indices.contains(nav.selectedIndex) { run(items[nav.selectedIndex]) }
                return .handled
            }
        }
    }

    // MARK: Grid page

    @ViewBuilder
    private func gridBody(_ items: [LauncherItem], columns: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        VStack(spacing: 2) {
                            Text(String(item.title.prefix(2)))
                                .font(.system(size: 26))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(index == nav.selectedIndex ? accent.opacity(0.25) : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .focusable(false)
                        .help(item.subtitle ?? item.title)
                        .id(index)
                        .onTapGesture { run(item) }
                    }
                }
                .padding(8)
            }
            .onKeyPressCompatible(.upArrow) {
                move(-columns, count: items.count, proxy: proxy)
                return .handled
            }
            .onKeyPressCompatible(.downArrow) {
                move(columns, count: items.count, proxy: proxy)
                return .handled
            }
            .onKeyPressCompatible(.return) {
                if items.indices.contains(nav.selectedIndex) { run(items[nav.selectedIndex]) }
                return .handled
            }
        }
    }

    private func move(_ delta: Int, count: Int, proxy: ScrollViewProxy) {
        let next = nav.selectedIndex + delta
        guard next >= 0, next < count else { return }
        nav.selectedIndex = next
        proxy.scrollTo(next, anchor: .center)
    }

    private func run(_ item: LauncherItem) {
        guard let primary = item.primaryAction else { return }
        onOutcome(item, primary.perform())
    }
}

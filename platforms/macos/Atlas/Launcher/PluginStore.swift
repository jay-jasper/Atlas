import Foundation
import SwiftUI

enum PluginStoreCategory: String, CaseIterable, Identifiable {
    case aiExtensions = "AI Extensions"
    case applications = "Applications"
    case communication = "Communication"
    case data = "Data"
    case documentation = "Documentation"
    case designTools = "Design Tools"
    case developerTools = "Developer Tools"
    case finance = "Finance"
    case fun = "Fun"
    case media = "Media"
    case news = "News"
    case productivity = "Productivity"
    case security = "Security"
    case system = "System"
    case web = "Web"
    case other = "Other"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aiExtensions: return loc("AI 扩展", "AI Extensions")
        case .applications: return loc("应用", "Applications")
        case .communication: return loc("通信", "Communication")
        case .data: return loc("数据", "Data")
        case .documentation: return loc("文档", "Documentation")
        case .designTools: return loc("设计工具", "Design Tools")
        case .developerTools: return loc("开发者工具", "Developer Tools")
        case .finance: return loc("金融", "Finance")
        case .fun: return loc("娱乐", "Fun")
        case .media: return loc("媒体", "Media")
        case .news: return loc("新闻", "News")
        case .productivity: return loc("效率", "Productivity")
        case .security: return loc("安全", "Security")
        case .system: return loc("系统", "System")
        case .web: return loc("网页", "Web")
        case .other: return loc("其他", "Other")
        }
    }

    var iconName: String {
        switch self {
        case .aiExtensions: return "sparkles"
        case .applications: return "app.badge"
        case .communication: return "megaphone"
        case .data: return "cpu"
        case .documentation: return "doc"
        case .designTools: return "pencil"
        case .developerTools: return "hammer"
        case .finance: return "banknote"
        case .fun: return "face.smiling"
        case .media: return "music.note"
        case .news: return "book"
        case .productivity: return "calendar"
        case .security: return "lock"
        case .system: return "display"
        case .web: return "globe"
        case .other: return "shippingbox"
        }
    }
}

struct MockPluginListing: Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String
    let author: String
    let category: PluginStoreCategory
    let downloads: Int
    let iconName: String
    let keywords: [String]
}

final class MockPluginStore: ObservableObject {
    static let installedDefaultsKey = "atlas.mockPluginStore.installedIDs"

    @Published private(set) var installedIDs: Set<String>
    @Published var selectedCategory: PluginStoreCategory?
    @Published var installedOnly = false

    let catalog: [MockPluginListing]

    private let defaults: UserDefaults
    private let installedDefaultsKey: String

    init(
        catalog: [MockPluginListing] = MockPluginStore.defaultCatalog,
        defaults: UserDefaults = .standard,
        installedDefaultsKey: String = MockPluginStore.installedDefaultsKey
    ) {
        self.catalog = catalog
        self.defaults = defaults
        self.installedDefaultsKey = installedDefaultsKey
        installedIDs = Set(defaults.stringArray(forKey: installedDefaultsKey) ?? [])
    }

    var categories: [PluginStoreCategory] {
        PluginStoreCategory.allCases
    }

    func isInstalled(_ listing: MockPluginListing) -> Bool {
        installedIDs.contains(listing.id)
    }

    func install(_ listing: MockPluginListing) {
        installedIDs.insert(listing.id)
        persistInstalledIDs()
    }

    func uninstall(_ listing: MockPluginListing) {
        installedIDs.remove(listing.id)
        persistInstalledIDs()
    }

    func listings(matching query: String) -> [MockPluginListing] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return catalog.filter { listing in
            let categoryMatches = selectedCategory == nil || listing.category == selectedCategory
            let installMatches = !installedOnly || isInstalled(listing)
            guard categoryMatches, installMatches, !term.isEmpty else {
                return categoryMatches && installMatches
            }
            return listing.name.localizedCaseInsensitiveContains(term)
                || listing.summary.localizedCaseInsensitiveContains(term)
                || listing.author.localizedCaseInsensitiveContains(term)
                || listing.category.rawValue.localizedCaseInsensitiveContains(term)
                || listing.category.title.localizedCaseInsensitiveContains(term)
                || listing.keywords.contains { $0.localizedCaseInsensitiveContains(term) }
        }
    }

    func launcherItems(matching query: String) -> [LauncherItem] {
        listings(matching: query).map(makeLauncherItem)
    }

    private func makeLauncherItem(_ listing: MockPluginListing) -> LauncherItem {
        let installed = isInstalled(listing)
        var actions = [
            LauncherAction(
                id: installed ? "installed" : "install",
                title: installed ? loc("已安装", "Installed") : loc("安装", "Install"),
                systemImage: installed ? "checkmark.circle.fill" : "square.and.arrow.down",
                shortcutHint: "↵"
            ) { [weak self] in
                guard let self else { return .stay }
                if !self.isInstalled(listing) {
                    self.install(listing)
                }
                return .stay
            },
        ]

        if installed {
            actions.append(
                LauncherAction(
                    id: "uninstall",
                    title: loc("卸载", "Uninstall"),
                    systemImage: "trash",
                    shortcutHint: nil
                ) { [weak self] in
                    self?.uninstall(listing)
                    return .stay
                }
            )
        }

        return LauncherItem(
            id: "PluginStore|\(listing.id)",
            title: listing.name,
            subtitle: "\(listing.summary) · \(Self.downloadText(listing.downloads)) \(loc("次下载", "downloads"))",
            icon: .sfSymbol(listing.iconName),
            keywords: listing.keywords + [
                listing.author,
                listing.category.rawValue,
                listing.category.title,
                "plugin",
                "store",
                "插件",
                "商店",
            ],
            category: loc("插件商店", "Plugin Store"),
            actions: actions,
            detail: LauncherDetail(rows: [
                .init(label: loc("发布者", "Publisher"), value: listing.author),
                .init(label: loc("分类", "Category"), value: listing.category.title),
                .init(label: loc("下载量", "Downloads"), value: Self.downloadText(listing.downloads)),
                .init(label: loc("来源", "Source"), value: loc("本地 Mock 目录", "Local mock catalog")),
            ])
        )
    }

    private func persistInstalledIDs() {
        defaults.set(Array(installedIDs).sorted(), forKey: installedDefaultsKey)
    }

    static func downloadText(_ downloads: Int) -> String {
        if AppLanguage.current == .en {
            if downloads >= 1_000_000 {
                return String(format: "%.1fM", Double(downloads) / 1_000_000)
                    .replacingOccurrences(of: ".0M", with: "M")
            }
            if downloads >= 1_000 {
                return String(format: "%.1fK", Double(downloads) / 1_000)
                    .replacingOccurrences(of: ".0K", with: "K")
            }
            return downloads.formatted()
        }
        if downloads >= 10_000 {
            return String(format: "%.1f万", Double(downloads) / 10_000)
                .replacingOccurrences(of: ".0万", with: "万")
        }
        return downloads.formatted()
    }

    static let defaultCatalog: [MockPluginListing] = [
        MockPluginListing(
            id: "linear",
            name: "Linear",
            summary: "Create, search, and update issues from Atlas.",
            author: "Linear",
            category: .productivity,
            downloads: 332_000,
            iconName: "line.3.horizontal.decrease.circle.fill",
            keywords: ["issues", "project", "tasks", "linear"]
        ),
        MockPluginListing(
            id: "google-translate",
            name: "Google Translate",
            summary: "Translate selected text and clipboard content.",
            author: "Atlas Community",
            category: .productivity,
            downloads: 428_000,
            iconName: "character.book.closed.fill",
            keywords: ["translate", "language", "翻译"]
        ),
        MockPluginListing(
            id: "spotify-player",
            name: "Spotify Player",
            summary: "Search music and control playback from the command panel.",
            author: "Community",
            category: .media,
            downloads: 420_000,
            iconName: "music.note.list",
            keywords: ["spotify", "music", "player", "音乐"]
        ),
        MockPluginListing(
            id: "visual-studio-code",
            name: "Visual Studio Code",
            summary: "Open projects, recent workspaces, and repositories.",
            author: "Community",
            category: .developerTools,
            downloads: 349_000,
            iconName: "chevron.left.forwardslash.chevron.right",
            keywords: ["vscode", "code", "editor", "developer"]
        ),
        MockPluginListing(
            id: "slack",
            name: "Slack",
            summary: "Search conversations and jump to unread messages.",
            author: "Atlas Community",
            category: .communication,
            downloads: 280_000,
            iconName: "bubble.left.and.bubble.right.fill",
            keywords: ["slack", "chat", "messages", "聊天"]
        ),
        MockPluginListing(
            id: "one-password",
            name: "1Password",
            summary: "Find vault items and copy credentials securely.",
            author: "Community",
            category: .security,
            downloads: 205_000,
            iconName: "lock.shield.fill",
            keywords: ["password", "vault", "security", "密码"]
        ),
        MockPluginListing(
            id: "eight-ball",
            name: "8 Ball",
            summary: "Ask a question and get a delightfully decisive answer.",
            author: "rocksack",
            category: .fun,
            downloads: 82_000,
            iconName: "8.circle.fill",
            keywords: ["8 ball", "raycast", "answer", "fun"]
        ),
    ]
}

struct PluginStoreSource: LauncherItemSource {
    let sourceID = "plugin-store"
    let store: MockPluginStore

    func items(for query: String) -> [LauncherItem] {
        [
            LauncherItem(
                id: "PluginStore|Open",
                title: loc("插件商店", "Plugin Store"),
                subtitle: loc("浏览并安装本地 Mock 目录中的扩展", "Browse and install extensions from the local mock catalog"),
                icon: .sfSymbol("shippingbox.fill"),
                keywords: [
                    "plugin",
                    "plugins",
                    "store",
                    "extension",
                    "extensions",
                    "插件",
                    "商店",
                    "插件商店",
                    "扩展",
                ],
                category: loc("插件商店", "Plugin Store"),
                actions: [
                    LauncherAction(
                        id: "open",
                        title: loc("打开商店", "Open Store"),
                        systemImage: "arrow.right",
                        shortcutHint: "↵"
                    ) { [store] in
                        .push(.pluginStore(title: loc("插件商店", "Plugin Store"), store: store))
                    },
                ]
            ),
        ]
    }
}

struct PluginStorePageView: View {
    @ObservedObject var store: MockPluginStore
    @ObservedObject var nav: LauncherNavigationModel
    let style: LauncherStyle
    let accent: Color
    let onOutcome: (LauncherItem, LauncherActionOutcome) -> Void

    private var listings: [MockPluginListing] {
        store.listings(matching: nav.query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(filterTitle)
                    .font(.system(size: style.fontSize - 1, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    Button {
                        store.selectedCategory = nil
                        store.installedOnly = false
                        nav.selectedIndex = 0
                    } label: {
                        Label(loc("全部分类", "All Categories"), systemImage: "list.bullet.rectangle")
                    }
                    Button {
                        store.selectedCategory = nil
                        store.installedOnly = true
                        nav.selectedIndex = 0
                    } label: {
                        Label(loc("已安装", "Installed"), systemImage: "checkmark.circle")
                    }
                    Divider()
                    ForEach(store.categories) { category in
                        Button {
                            store.selectedCategory = category
                            store.installedOnly = false
                            nav.selectedIndex = 0
                        } label: {
                            Label(category.title, systemImage: category.iconName)
                        }
                    }
                } label: {
                    Label(filterTitle, systemImage: filterIconName)
                        .font(.system(size: style.fontSize - 1))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 14)
            .frame(height: 42)

            Divider().opacity(0.35)

            if listings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text(loc("没有找到扩展", "No extensions found"))
                        .font(.system(size: style.fontSize))
                    Text(loc("请尝试其他搜索词或分类。", "Try another search or category."))
                        .font(.system(size: style.fontSize - 2))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(listings.enumerated()), id: \.element.id) { index, listing in
                        row(listing, index: index)
                            .id(index)
                    }
                }
                .padding(8)
            }
            .onKeyPressCompatible(.upArrow) {
                move(-1, proxy: proxy)
                return .handled
            }
            .onKeyPressCompatible(.downArrow) {
                move(1, proxy: proxy)
                return .handled
            }
            .onKeyPressCompatible(.return) {
                installSelected()
                return .handled
            }
            .onChange(of: nav.selectedIndex) { index in
                guard listings.indices.contains(index) else { return }
                proxy.scrollTo(index, anchor: .center)
            }
        }
    }

    private func row(_ listing: MockPluginListing, index: Int) -> some View {
        let installed = store.isInstalled(listing)
        return HStack(spacing: 12) {
            LauncherIconView(icon: .sfSymbol(listing.iconName), size: 30, accent: accent)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(listing.name)
                    .font(.system(size: style.fontSize + 1, weight: .medium))
                    .lineLimit(1)
                Text(listing.summary)
                    .font(.system(size: style.fontSize - 1))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(listing.category.title)
                .font(.system(size: style.fontSize - 3))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Label(MockPluginStore.downloadText(listing.downloads), systemImage: "arrow.down.circle")
                .font(.system(size: style.fontSize - 2))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .frame(minWidth: 72, alignment: .trailing)

            Button {
                run(listing)
            } label: {
                if installed {
                    Label(loc("已安装", "Installed"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label(loc("安装", "Install"), systemImage: "square.and.arrow.down")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(installed)
            .frame(width: 92)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 58)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(index == nav.selectedIndex ? accent.opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            nav.selectedIndex = index
        }
    }

    private func move(_ delta: Int, proxy: ScrollViewProxy) {
        nav.moveSelection(by: delta, itemCount: listings.count)
        proxy.scrollTo(nav.selectedIndex, anchor: .center)
    }

    private func installSelected() {
        guard listings.indices.contains(nav.selectedIndex) else { return }
        run(listings[nav.selectedIndex])
    }

    private func run(_ listing: MockPluginListing) {
        guard let item = store.launcherItems(matching: nav.query)
            .first(where: { $0.id == "PluginStore|\(listing.id)" }),
              let primary = item.primaryAction
        else { return }
        onOutcome(item, primary.perform())
        nav.selectedIndex = nav.selectedIndex
    }

    private var filterTitle: String {
        if store.installedOnly {
            return loc("已安装", "Installed")
        }
        guard let category = store.selectedCategory else {
            return loc("全部分类", "All Categories")
        }
        return category.title
    }

    private var filterIconName: String {
        if store.installedOnly {
            return "checkmark.circle"
        }
        guard let category = store.selectedCategory else {
            return "list.bullet.rectangle"
        }
        return category.iconName
    }
}

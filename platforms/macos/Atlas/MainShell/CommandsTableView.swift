import SwiftUI

/// Raycast Extensions 式命令表格:名称 / 分类 / Alias(内联编辑)/ 热键 / 收藏。
struct CommandsTableView: View {
    @ObservedObject var aliases: AliasStore
    @ObservedObject var hotkeys: CommandHotkeyStore
    @ObservedObject var favorites: FavoritesStore
    let hotkeyConflicts: [String: String]
    let rootItems: () -> [LauncherItem]

    @State private var query = ""
    @State private var selectedCategory: String?
    @State private var items: [LauncherItem] = []

    private var categories: [String] {
        var seen = Set<String>()
        return items.map(\.category).filter { seen.insert($0).inserted }
    }

    private var filtered: [LauncherItem] {
        items.filter { item in
            (selectedCategory == nil || item.category == selectedCategory)
                && (query.isEmpty
                    || item.title.localizedCaseInsensitiveContains(query)
                    || (aliases.alias(for: item.id)?.localizedCaseInsensitiveContains(query) ?? false))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("命令")
                .font(.title3.weight(.semibold))
            Text("为启动台命令设置 Alias 与独立热键,收藏的命令置顶显示。")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索命令或 Alias", text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                .frame(maxWidth: 260)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        categoryChip(nil, label: "全部")
                        ForEach(categories, id: \.self) { category in
                            categoryChip(category, label: category)
                        }
                    }
                }
            }

            headerRow
            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { item in
                        CommandTableRow(
                            item: item,
                            aliases: aliases,
                            hotkeys: hotkeys,
                            favorites: favorites,
                            conflict: hotkeyConflicts[item.id]
                        )
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .padding(14)
        .onAppear { items = rootItems() }
    }

    private func categoryChip(_ category: String?, label: String) -> some View {
        Button {
            selectedCategory = category
        } label: {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(
                        selectedCategory == category
                            ? Color.accentColor.opacity(0.2)
                            : Color.primary.opacity(0.06)
                    )
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("名称").frame(maxWidth: .infinity, alignment: .leading)
            Text("分类").frame(width: 110, alignment: .leading)
            Text("Alias").frame(width: 110, alignment: .leading)
            Text("热键").frame(width: 150, alignment: .leading)
            Text("收藏").frame(width: 36, alignment: .center)
        }
        .font(.caption.weight(.semibold))
        .foregroundColor(.secondary)
    }
}

private struct CommandTableRow: View {
    let item: LauncherItem
    @ObservedObject var aliases: AliasStore
    @ObservedObject var hotkeys: CommandHotkeyStore
    @ObservedObject var favorites: FavoritesStore
    let conflict: String?

    @State private var aliasDraft: String = ""

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                LauncherIconView(icon: item.icon, size: 22, accent: .accentColor)
                Text(item.title)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.category)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)

            TextField("添加", text: $aliasDraft, onCommit: {
                aliases.setAlias(aliasDraft, for: item.id)
                aliasDraft = aliases.alias(for: item.id) ?? ""
            })
            .textFieldStyle(.plain)
            .font(.caption.monospaced())
            .frame(width: 110, alignment: .leading)
            .onAppear { aliasDraft = aliases.alias(for: item.id) ?? "" }

            VStack(alignment: .leading, spacing: 2) {
                KeyRecorderView { config in
                    hotkeys.set(config, for: item.id)
                }
                .frame(width: 140)
                if let conflict {
                    Text(conflict)
                        .font(.system(size: 9))
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
            .frame(width: 150, alignment: .leading)

            Button {
                favorites.toggle(item.id)
            } label: {
                Image(systemName: favorites.isPinned(item.id) ? "star.fill" : "star")
                    .foregroundColor(favorites.isPinned(item.id) ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .frame(width: 36, alignment: .center)
        }
        .padding(.vertical, 5)
        .focusable(false)
    }
}

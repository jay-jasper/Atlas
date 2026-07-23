import SwiftUI

/// 片段页:自动展开开关 + 权限区 + 关键词管理(片段本体沿用 SnippetStore)。
struct RaycastSnippetsView: View {
    @ObservedObject private var service = SnippetExpansionService.shared
    @State private var snippets: [Snippet] = []
    @State private var keywords: [String: String] = [:]
    private let store = SnippetStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PermissionStatusSection(permissions: [.accessibility])

            SettingsSection(title: loc("自动展开", "Auto Expand")) {
                SettingsRow(
                    icon: "text.badge.plus",
                    title: loc("全局自动展开", "Expand while typing"),
                    description: loc(
                        "任意 app 里输入关键词即展开片段。支持 {clipboard} {date} {time} {uuid} {cursor} {argument:提示}。",
                        "Typing a keyword anywhere expands the snippet. Supports {clipboard} {date} {time} {uuid} {cursor} {argument:prompt}."
                    )
                ) {
                    Toggle("", isOn: $service.isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            SettingsSection(title: loc("片段关键词", "Snippet Keywords")) {
                if snippets.isEmpty {
                    SettingsRow(
                        icon: "tray",
                        title: loc("暂无片段", "No snippets"),
                        description: loc("在启动台的 Snippets 命令里新建片段。", "Create snippets via the launcher's Snippets command.")
                    ) { EmptyView() }
                } else {
                    ForEach(Array(snippets.enumerated()), id: \.element.id) { index, snippet in
                        SettingsRow(
                            icon: "doc.text",
                            title: snippet.title,
                            description: String(snippet.body.prefix(60))
                        ) {
                            TextField(
                                loc("关键词(如 ;mail)", "keyword (e.g. ;mail)"),
                                text: keywordBinding(snippet.id)
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                        }
                        if index < snippets.count - 1 {
                            SettingsRowDivider()
                        }
                    }
                }
            }
        }
        .onAppear {
            snippets = store.snippets()
            keywords = SnippetKeywordStore.all()
        }
    }

    private func keywordBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { keywords[id] ?? "" },
            set: { newValue in
                keywords[id] = newValue
                SnippetKeywordStore.set(newValue, for: id)
                service.reloadEntries()
            }
        )
    }
}

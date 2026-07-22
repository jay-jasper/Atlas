import SwiftUI

/// 功能面板配置页:菜单栏组件启用 / 排序(MacTools 功能面板配置同构)。
struct MenuPanelConfigView: View {
    @ObservedObject var store: WidgetStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    IconTile(systemImage: "slider.horizontal.3", tint: .purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("功能面板")
                            .font(.title3.weight(.semibold))
                        Text("选择在菜单栏组件面板显示的组件,再调整顺序。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                SettingsCard {
                    ForEach(Array(WidgetKind.allCases.enumerated()), id: \.element) { index, kind in
                        SettingsRow(
                            icon: kind.icon,
                            tint: store.isEnabled(kind) ? .accentColor : .gray,
                            title: kind.title,
                            description: kind.summary
                        ) {
                            HStack(spacing: 10) {
                                if store.isEnabled(kind) {
                                    Button {
                                        store.moveUp(kind)
                                    } label: {
                                        Image(systemName: "chevron.up").font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(store.enabled.first == kind)
                                    Button {
                                        store.moveDown(kind)
                                    } label: {
                                        Image(systemName: "chevron.down").font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(store.enabled.last == kind)
                                }
                                Toggle("", isOn: Binding(
                                    get: { store.isEnabled(kind) },
                                    set: { enabled in
                                        if enabled { store.add(kind) } else { store.remove(kind) }
                                    }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                            }
                        }
                        if index < WidgetKind.allCases.count - 1 {
                            SettingsRowDivider()
                        }
                    }
                }

                if !store.enabled.isEmpty {
                    Text("当前顺序:\(store.enabled.map(\.title).joined(separator: " → "))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: 680, alignment: .leading)
        }
    }
}

import SwiftUI

/// 插件 tab:MacTools 式左侧栏 + 右详情。
/// 工具页内容由 ContentView 经闭包注入(section 枚举对外不可见,用 AnyHashable tag)。
struct PluginsTab: View {
    struct ToolEntry: Identifiable {
        let id: AnyHashable
        let title: String
        let icon: String
    }

    enum Selection: Hashable {
        case dashboard
        case menuPanel
        case commands
        case market
        case tool(AnyHashable)
    }

    @Binding var selection: Selection
    let toolEntries: [ToolEntry]
    let dashboardView: () -> AnyView
    let menuPanelConfigView: () -> AnyView
    let commandsView: () -> AnyView
    let marketView: () -> AnyView
    let toolView: (AnyHashable) -> AnyView

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 210)
            Divider().opacity(0.35)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                sidebarHeader(loc("插件", "Plugins"))
                sidebarRow(.dashboard, title: loc("仪表盘", "Dashboard"), icon: "square.grid.2x2")
                sidebarRow(.menuPanel, title: loc("功能面板", "Panel Widgets"), icon: "slider.horizontal.3")
                sidebarRow(.commands, title: loc("命令", "Commands"), icon: "keyboard")
                sidebarRow(.market, title: loc("市场", "Market"), icon: "shippingbox")

                if !toolEntries.isEmpty {
                    sidebarHeader(loc("工具设置", "Tool Settings"))
                        .padding(.top, 10)
                    ForEach(toolEntries) { entry in
                        sidebarRow(.tool(entry.id), title: entry.title, icon: entry.icon)
                    }
                }
            }
            .padding(8)
        }
    }

    private func sidebarHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
    }

    private func sidebarRow(_ target: Selection, title: String, icon: String) -> some View {
        Button {
            selection = target
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selection == target ? Color.accentColor.opacity(0.16) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .dashboard:
            dashboardView()
        case .menuPanel:
            menuPanelConfigView()
        case .commands:
            commandsView()
        case .market:
            marketView()
        case .tool(let tag):
            toolView(tag)
        }
    }
}

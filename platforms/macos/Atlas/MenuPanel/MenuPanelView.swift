import SwiftUI

/// 菜单栏面板:只保留组件面板;右上角 主窗口 / 退出 图标。
struct MenuPanelView: View {
    @ObservedObject var widgetStore: WidgetStore
    let widgetContent: (WidgetKind) -> AnyView
    let statusBanner: AnyView?
    let onOpenMainWindow: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            header

            if let statusBanner {
                statusBanner
            }

            WidgetBoardPanel(store: widgetStore, content: widgetContent)
        }
        .padding(10)
        .noDefaultFocus()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(loc("组件", "Widgets"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            Spacer()

            Button(action: onOpenMainWindow) {
                Image(systemName: "macwindow")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(loc("打开主窗口", "Open Main Window"))

            Button(action: onQuit) {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(loc("退出", "Quit"))
        }
        .frame(height: 24)
    }
}

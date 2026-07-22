import SwiftUI

/// 菜单栏面板:只保留组件面板;右上角 主窗口 / 退出 图标。
struct MenuPanelView: View {
    @ObservedObject var widgetStore: WidgetStore
    let widgetContent: (WidgetKind) -> AnyView
    let statusBanner: AnyView?
    let onOpenMainWindow: () -> Void
    let onQuit: () -> Void

    @AppStorage("atlas.shell.theme") private var shellThemeRaw = ShellThemeKind.plain.rawValue
    @State private var isShowingThemePicker = false

    private var theme: ShellThemeKind {
        ShellThemeKind(rawValue: shellThemeRaw) ?? .plain
    }

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
            Button(action: onQuit) {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(loc("退出", "Quit"))

            Button(action: onOpenMainWindow) {
                Image(systemName: "macwindow")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(loc("打开主窗口", "Open Main Window"))

            Spacer()

            Button {
                isShowingThemePicker.toggle()
            } label: {
                Image(systemName: theme.spec.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: theme.spec.swatchColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .black.opacity(0.25), radius: 2)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(loc("主题", "Theme"))
            .popover(isPresented: $isShowingThemePicker, arrowEdge: .bottom) {
                ShellThemePickerPanel(selectionRaw: $shellThemeRaw) {
                    isShowingThemePicker = false
                }
            }
        }
        .frame(height: 24)
    }
}

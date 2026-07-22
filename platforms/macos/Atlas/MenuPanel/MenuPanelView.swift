import SwiftUI

/// MacTools 式菜单栏双面板容器:顶部居中 功能/组件 切换器,底部固定行,
/// 箭头行推入二级页(sectionBuilder 由 ContentView 提供)。
struct MenuPanelView: View {
    let featureGroups: [FeatureListPanel.Group]
    @ObservedObject var widgetStore: WidgetStore
    let widgetContent: (WidgetKind) -> AnyView
    let sectionBuilder: (AnyHashable) -> AnyView
    let sectionTitle: (AnyHashable) -> String
    let statusBanner: AnyView?
    let onOpenMainWindow: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    @AppStorage("menuPanel.mode") private var modeRaw = PanelMode.features.rawValue
    @State private var pushedTag: AnyHashable?

    private var mode: PanelMode {
        PanelMode(rawValue: modeRaw) ?? .features
    }

    var body: some View {
        VStack(spacing: 8) {
            if let pushedTag {
                subPageHeader(tag: pushedTag)
                ScrollView {
                    sectionBuilder(pushedTag)
                        .padding(.bottom, 4)
                }
            } else {
                switcher

                if let statusBanner {
                    statusBanner
                }

                switch mode {
                case .features:
                    FeatureListPanel(groups: featureGroups) { tag in
                        withAnimation(.easeInOut(duration: 0.15)) { pushedTag = tag }
                    }
                case .widgets:
                    WidgetBoardPanel(store: widgetStore, content: widgetContent)
                }

                Divider()
                bottomRows
            }
        }
        .padding(10)
        .noDefaultFocus()
    }

    // MARK: Switcher

    private var switcher: some View {
        HStack(spacing: 2) {
            ForEach(PanelMode.allCases) { candidate in
                Button {
                    modeRaw = candidate.rawValue
                } label: {
                    Text(candidate.title)
                        .font(.system(size: 12, weight: mode == candidate ? .semibold : .regular))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(mode == candidate ? Color.accentColor.opacity(0.22) : Color.clear)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .padding(3)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        .frame(maxWidth: .infinity)
    }

    // MARK: Sub-page

    private func subPageHeader(tag: AnyHashable) -> some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { pushedTag = nil }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("返回")
                }
                .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .focusable(false)

            Spacer()

            Text(sectionTitle(tag))
                .font(.system(size: 12, weight: .semibold))

            Spacer()

            // Balance the back button so the title stays centered.
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("返回")
            }
            .font(.system(size: 12, weight: .medium))
            .hidden()
        }
    }

    // MARK: Bottom fixed rows

    private var bottomRows: some View {
        HStack(spacing: 0) {
            bottomButton("打开主窗口", icon: "macwindow", action: onOpenMainWindow)
            Divider().frame(height: 16)
            bottomButton("设置", icon: "gearshape", action: onOpenSettings)
            Divider().frame(height: 16)
            bottomButton("退出", icon: "power", action: onQuit)
        }
        .frame(height: 30)
    }

    private func bottomButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

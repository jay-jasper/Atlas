import SwiftUI

/// 组件面板:按 WidgetStore 顺序渲染卡片,右键 移除/上移/下移,底部添加入口。
struct WidgetBoardPanel: View {
    @ObservedObject var store: WidgetStore
    let content: (WidgetKind) -> AnyView

    @State private var isGalleryShown = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(store.enabled) { kind in
                    content(kind)
                        .contextMenu {
                            Button("上移") { store.moveUp(kind) }
                                .disabled(store.enabled.first == kind)
                            Button("下移") { store.moveDown(kind) }
                                .disabled(store.enabled.last == kind)
                            Divider()
                            Button("移除", role: .destructive) { store.remove(kind) }
                        }
                }

                Button {
                    isGalleryShown = true
                } label: {
                    Label("添加组件", systemImage: "plus")
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundColor(.secondary.opacity(0.5))
                )
                .focusable(false)
            }
            .padding(.vertical, 2)
        }
        .sheet(isPresented: $isGalleryShown) {
            WidgetGalleryView(store: store)
        }
    }
}

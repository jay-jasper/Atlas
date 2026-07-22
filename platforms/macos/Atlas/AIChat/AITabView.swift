import SwiftUI

/// AI tab:直接展示 本机 CLI / BYOK 引擎配置(聊天界面已下线)。
struct AITabView: View {
    @StateObject private var bridge = AIChatBridge()

    var body: some View {
        ScrollView {
            AIConfigSheet(bridge: bridge, engineStore: bridge.engineStore, embedded: true)
                .glassCard(padding: 4)
                .frame(maxWidth: 760, alignment: .topLeading)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
    }
}

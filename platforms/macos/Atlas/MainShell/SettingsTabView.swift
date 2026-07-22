import SwiftUI

/// 设置 tab:主题选择 + 共享设置面板(与独立设置窗复用同一批组件)。
struct SettingsTabView: View {
    @Binding var shellThemeRaw: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("外观主题")
                    .font(.title3.weight(.semibold))
                ShellThemePickerPanel(selectionRaw: $shellThemeRaw) {}
                    .glassCard(padding: 12)

                Divider()

                SettingsPanelsHost(paletteState: AtlasServices.shared.paletteState)
                    .glassCard(padding: 12)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

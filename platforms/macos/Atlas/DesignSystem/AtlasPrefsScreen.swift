import SwiftUI

/// Faithful recreation of the prototype's Preferences window (`Atlas Prefs.dc.html`):
/// a 720×560 window with a traffic-light title bar, a left settings sidebar (截图
/// selected), and a right pane showing the Screenshot module's sub-features,
/// output options, and annotation-style controls, plus an unsaved-changes footer.
struct AtlasPrefsScreen: View {
    @Environment(\.colorScheme) private var scheme
    var onClose: () -> Void = {}
    var onOpenEdition: () -> Void = {}

    private struct NavItem: Identifiable {
        let id = UUID(); let icon: String; let name: String
        var kbd: String? = nil; var pro: Bool = false; var selected: Bool = false
    }
    private let navItems: [NavItem] = [
        NavItem(icon: "gearshape", name: "通用"),
        NavItem(icon: "keyboard", name: "热键", kbd: "⌘⇧A"),
        NavItem(icon: "viewfinder", name: "截图", selected: true),
        NavItem(icon: "character.bubble", name: "翻译"),
        NavItem(icon: "clock.badge", name: "TokenBar"),
        NavItem(icon: "wand.and.stars", name: "自动化"),
        NavItem(icon: "sparkles", name: "AI Skills"),
    ]
    private let navItemsBottom: [NavItem] = [
        NavItem(icon: "square.stack.3d.up", name: "版本", kbd: "Pro", pro: true),
        NavItem(icon: "info.circle", name: "关于"),
    ]

    private struct SubFeature: Identifiable { let id = UUID(); let name: String; let kbd: String; let on: Bool }
    private let subFeatures: [SubFeature] = [
        SubFeature(name: "区域截图", kbd: "⌘⇧4", on: true),
        SubFeature(name: "窗口截图", kbd: "⌘⇧4 ⎵", on: true),
        SubFeature(name: "全屏截图", kbd: "⌘⇧3", on: true),
        SubFeature(name: "滚动截图", kbd: "⌘⇧5", on: true),
        SubFeature(name: "GIF 录屏", kbd: "⌘⇧6", on: false),
        SubFeature(name: "钉住缩略图", kbd: "浮动小窗", on: true),
    ]

    private let annotationColors: [Color] = [
        Color(hex: "FF5F57"), Color(hex: "FEBC2E"), Color(hex: "28C840"),
        Color(hex: "2F7FE0"), Color(hex: "B05AE8"), Color(hex: "FFFFFF"), Color(hex: "1d1d1f"),
    ]

    var body: some View {
        let theme = AtlasTheme.resolve(for: scheme)
        AtlasPopupChrome {
            VStack(spacing: 0) {
                titleBar(theme)
                HStack(spacing: 0) {
                    sidebar(theme)
                    Rectangle().fill(theme.divider).frame(width: 1)
                    detailPane(theme)
                }
                footer(theme)
            }
        }
        .frame(width: 720, height: 560)
        .environment(\.atlasTheme, theme)
    }

    // MARK: - Title bar

    private func titleBar(_ theme: AtlasTheme) -> some View {
        HStack {
            HStack(spacing: 7) {
                trafficLight(theme.red); trafficLight(theme.orange); trafficLight(theme.green)
            }
            Spacer(minLength: 0)
            (Text("Preferences ").fontWeight(.semibold).foregroundColor(theme.text1)
                + Text("— Atlas").foregroundColor(theme.text3))
                .font(.system(size: 12.5))
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Circle().fill(theme.orange).frame(width: 5, height: 5)
                Text("未保存").font(.system(size: 10.5)).foregroundStyle(theme.text3)
            }
        }
        .padding(.horizontal, 14).frame(height: 38)
        .background(theme.section)
        .overlay(Rectangle().fill(theme.divider).frame(height: 1), alignment: .bottom)
    }

    private func trafficLight(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 12, height: 12)
    }

    // MARK: - Sidebar

    private func sidebar(_ theme: AtlasTheme) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("设置").font(.system(size: 10, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(theme.text3)
                    .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 8)
                ForEach(navItems) { navButton(theme, $0) }
                Rectangle().fill(theme.divider).frame(height: 1).padding(.horizontal, 10).padding(.vertical, 8)
                ForEach(navItemsBottom) { navButton(theme, $0) }
            }
            .padding(.horizontal, 8).padding(.vertical, 14)
        }
        .frame(width: 188)
        .background(theme.section)
    }

    private func navButton(_ theme: AtlasTheme, _ item: NavItem) -> some View {
        Button { if item.name == "版本" { onOpenEdition() } } label: {
            HStack(spacing: 9) {
                Image(systemName: item.icon).font(.system(size: 12))
                    .foregroundStyle(item.selected ? theme.accentText : theme.text2)
                    .frame(width: 18)
                Text(item.name).font(.system(size: 12.5, weight: item.selected ? .medium : .regular))
                    .foregroundStyle(theme.text1)
                Spacer(minLength: 0)
                if let kbd = item.kbd {
                    Text(kbd).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(item.pro ? theme.accentText : theme.text3)
                        .fontWeight(item.pro ? .medium : .regular)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(item.selected ? theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail pane

    private func detailPane(_ theme: AtlasTheme) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("截图").font(.system(size: 17, weight: .semibold))
                    Text("区域 · 窗口 · 滚动 · GIF · OCR · 标注")
                        .font(.system(size: 11.5)).foregroundStyle(theme.text3)
                }
                subFeaturesBlock(theme)
                outputBlock(theme)
                annotationBlock(theme)
            }
            .padding(.horizontal, 22).padding(.vertical, 18)
        }
        .frame(maxWidth: .infinity)
        .background(theme.popupSolid)
    }

    private func sectionLabel(_ theme: AtlasTheme, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.7).foregroundStyle(theme.text3)
            Rectangle().fill(theme.divider).frame(height: 1)
        }
    }

    private func subFeaturesBlock(_ theme: AtlasTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(theme, "子功能")
            let columns = [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)]
            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(subFeatures) { checkCard(theme, $0) }
            }
        }
    }

    private func checkCard(_ theme: AtlasTheme, _ feat: SubFeature) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(feat.on ? theme.accent : .clear)
                    .frame(width: 15, height: 15)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(feat.on ? theme.accent : theme.borderStrong, lineWidth: 1.5))
                if feat.on {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(feat.name).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.text1)
                Text(feat.kbd).font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.text3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(feat.on ? theme.accentSoft : theme.section, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(feat.on ? theme.accentStrong : theme.divider, lineWidth: 1))
    }

    private func outputBlock(_ theme: AtlasTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(theme, "输出")
            field(theme, "格式") {
                VStack(alignment: .leading, spacing: 4) {
                    segmented(theme, ["PNG", "JPG", "WebP", "HEIC"], selected: "PNG")
                    Text("PNG 无损,适合截图;HEIC 体积最小但 macOS 13+ 才能完整预览。")
                        .font(.system(size: 10.5)).foregroundStyle(theme.text3)
                }
            }
            field(theme, "保存到") {
                HStack(spacing: 8) {
                    inputField(theme, "~/Pictures/Atlas/Screenshots", mono: true)
                    Button("选择...") {}.buttonStyle(.plain)
                        .font(.system(size: 11.5)).foregroundStyle(theme.text1)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(theme.input, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.borderInput, lineWidth: 1))
                }
            }
            field(theme, "文件名") {
                VStack(alignment: .leading, spacing: 4) {
                    inputField(theme, "Screenshot {scene}-{yyyy}{MM}{dd}-{HHmm}{ss}", mono: true)
                    Text("变量:{scene} {app} {window} {yyyy} {MM} {dd} {HH} {mm} {ss}")
                        .font(.system(size: 10.5)).foregroundStyle(theme.text3)
                }
            }
            field(theme, "OCR") {
                segmented(theme, ["关闭", "手动 (⌘⌥O)", "自动识别后入剪贴板"], selected: "手动 (⌘⌥O)")
            }
        }
    }

    private func annotationBlock(_ theme: AtlasTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(theme, "标注样式")
            field(theme, "默认颜色") {
                HStack(spacing: 6) {
                    ForEach(Array(annotationColors.enumerated()), id: \.offset) { idx, c in
                        RoundedRectangle(cornerRadius: 5).fill(c).frame(width: 22, height: 22)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.border, lineWidth: idx == 5 ? 1 : 0))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.accent, lineWidth: idx == 0 ? 2 : 0).padding(-2))
                    }
                }
            }
            field(theme, "线条粗细") { sliderRow(theme, fraction: 0.45, label: "3.0 px") }
            field(theme, "字体大小") { sliderRow(theme, fraction: 0.30, label: "14 pt") }
            field(theme, "") { previewCard(theme) }
        }
    }

    private func previewCard(_ theme: AtlasTheme) -> some View {
        HStack(spacing: 16) {
            ZStack {
                LinearGradient(colors: [Color(hex: "2c3e50"), Color(hex: "4ca1af")],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RoundedRectangle(cornerRadius: 2).stroke(Color(hex: "FF5F57"), lineWidth: 2.5)
                    .frame(width: 80, height: 32).offset(x: -20)
                Text("点击这里").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).offset(x: -20)
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: "FF5F57")).offset(x: 55)
            }
            .frame(height: 60).clipShape(RoundedRectangle(cornerRadius: 4))
            (Text("实时预览\n").foregroundColor(theme.text3)
                + Text("箭头 / 矩形 / 文字").foregroundColor(theme.text3))
                .font(.system(size: 10)).frame(width: 100, alignment: .leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(theme.section, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.divider, lineWidth: 1))
    }

    // MARK: - Reusable controls

    private func field<Content: View>(_ theme: AtlasTheme, _ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label).font(.system(size: 12)).foregroundStyle(theme.text2)
                .frame(width: 110, alignment: .trailing).padding(.top, 3)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func segmented(_ theme: AtlasTheme, _ options: [String], selected: String) -> some View {
        HStack(spacing: 1.5) {
            ForEach(options, id: \.self) { opt in
                Text(opt).font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(opt == selected ? theme.text1 : theme.text2)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(opt == selected ? theme.popupSolid : .clear, in: RoundedRectangle(cornerRadius: 4.5))
                    .overlay(RoundedRectangle(cornerRadius: 4.5).stroke(opt == selected ? theme.borderStrong : .clear, lineWidth: 0.5))
            }
        }
        .padding(1.5)
        .background(theme.input, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.border, lineWidth: 1))
    }

    private func inputField(_ theme: AtlasTheme, _ value: String, mono: Bool) -> some View {
        Text(value)
            .font(.system(size: 11.5, design: mono ? .monospaced : .default))
            .foregroundStyle(theme.text1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(theme.input, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.borderInput, lineWidth: 1))
    }

    private func sliderRow(_ theme: AtlasTheme, fraction: Double, label: String) -> some View {
        HStack(spacing: 12) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.input).frame(height: 4)
                    Capsule().fill(theme.accent).frame(width: geo.size.width * fraction, height: 4)
                    Circle().fill(.white).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(theme.borderStrong, lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                        .offset(x: geo.size.width * fraction - 7)
                }
            }
            .frame(height: 14)
            Text(label).font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.text2)
                .frame(width: 40, alignment: .leading)
        }
    }

    private func footer(_ theme: AtlasTheme) -> some View {
        HStack(spacing: 10) {
            Text("3 项更改 · 未保存").font(.system(size: 11.5)).foregroundStyle(theme.text3)
            Spacer(minLength: 0)
            Button("取消", action: onClose).buttonStyle(.plain)
                .font(.system(size: 11.5)).foregroundStyle(theme.text1)
                .padding(.horizontal, 14).padding(.vertical, 5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.borderInput, lineWidth: 1))
            Button("保存") {}.buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 5)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 5))
        }
        .padding(.horizontal, 16).frame(height: 40)
        .background(theme.section)
        .overlay(Rectangle().fill(theme.divider).frame(height: 1), alignment: .top)
    }
}

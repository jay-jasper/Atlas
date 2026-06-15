import SwiftUI

/// The clickable design prototype (`Atlas Prototype.dc.html`) realized in SwiftUI:
/// a single host that navigates between the six approved screens exactly as the
/// mockup's `onNav` wiring does. This is a faithful design reference / preview
/// surface — the production app drives the same views from real services.
struct AtlasPrototypeView: View {
    enum Screen { case shell, palette, toggles, prefs, scene, edition }

    @State private var screen: Screen = .shell

    var body: some View {
        Group {
            switch screen {
            case .shell:
                AtlasShellView(
                    onOpenPalette: { screen = .palette },
                    onOpenPreferences: { screen = .prefs },
                    onOpenScene: { screen = .scene },
                    onOpenToggles: { screen = .toggles }
                )
            case .palette:
                AtlasPaletteScreen(onClose: { screen = .shell })
            case .toggles:
                AtlasTogglesScreen(onBack: { screen = .shell })
            case .prefs:
                AtlasPrefsScreen(onClose: { screen = .shell }, onOpenEdition: { screen = .edition })
            case .scene:
                AtlasSceneScreen(onClose: { screen = .shell })
            case .edition:
                AtlasEditionScreen(onBack: { screen = .prefs })
            }
        }
        .animation(.easeInOut(duration: 0.18), value: screen)
    }
}

#if DEBUG
struct AtlasPrototypeView_Previews: PreviewProvider {
    static var previews: some View {
        AtlasPrototypeView().preferredColorScheme(.dark)
        AtlasPrototypeView().preferredColorScheme(.light)
    }
}
#endif

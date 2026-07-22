import SwiftUI

struct AppFooter: View {
    var body: some View {
        HStack {
            Button("Settings") {
                AtlasServices.shared.openMainWindow?()
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

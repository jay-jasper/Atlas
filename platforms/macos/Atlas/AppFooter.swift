import SwiftUI

struct AppFooter: View {
    var body: some View {
        HStack {
            Button("Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

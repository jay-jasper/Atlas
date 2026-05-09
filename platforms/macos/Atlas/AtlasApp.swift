import SwiftUI

@main
struct AtlasApp: App {
    var body: some Scene {
        MenuBarExtra("Atlas", systemImage: "square.stack.3d.up.fill") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}

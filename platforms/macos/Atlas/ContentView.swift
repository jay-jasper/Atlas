import SwiftUI

struct ContentView: View {
    @State private var statusText: String = "Initializing..."

    var body: some View {
        VStack {
            Text(statusText)
                .font(.headline)
            
            Divider()
            
            Button("Settings") {
                NSApp.activate(ignoringOtherApps: true)
                // Opening settings UI will be implemented later
            }
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .onAppear {
            // This will eventually call the Rust Core via the UniFFI bridge
            statusText = "Atlas is Ready"
        }
    }
}

#Preview {
    ContentView()
}

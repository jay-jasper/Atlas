import SwiftUI

struct BrowserRouterPanel: View {
    @ObservedObject var service: BrowserRouterService
    @State private var pattern = ""
    @State private var selectedBrowser: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Browser Router", systemImage: "arrow.triangle.branch")
                .font(.headline)

            ForEach(service.routes) { route in
                HStack {
                    Text(route.pattern)
                        .font(.system(.caption, design: .monospaced))
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                    Text(route.browserName).font(.caption)
                    Spacer()
                    Button(role: .destructive) { service.delete(id: route.id) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            HStack {
                TextField("*.slack.com", text: $pattern)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $selectedBrowser) {
                    Text("Browser").tag("")
                    ForEach(service.installedBrowsers) { Text($0.name).tag($0.bundleID) }
                }
                .frame(width: 110)
                Button("Add") {
                    if let browser = service.installedBrowsers.first(where: { $0.bundleID == selectedBrowser }) {
                        service.addRoute(pattern: pattern, browser: browser)
                        pattern = ""
                    }
                }
                .disabled(pattern.isEmpty || selectedBrowser.isEmpty)
            }

            HStack {
                TextField("Test a URL…", text: $service.testURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { service.runTest() }
                Button("Test") { service.runTest() }
            }
            if !service.testResult.isEmpty {
                Text(service.testResult).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

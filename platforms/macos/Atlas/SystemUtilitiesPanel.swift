import SwiftUI

struct SystemUtilitiesPanelModel {
    let state: SystemUtilitiesState
    let onToggleKeepAwake: () -> Void
    let onTogglePresentationMode: () -> Void
    let onOpenHandMirror: () -> Void
    let onRefreshDisplays: () -> Void
}

struct SystemUtilitiesPanel: View {
    let model: SystemUtilitiesPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Utilities")
                .font(.headline)

            HStack {
                Button(keepAwakeTitle, action: model.onToggleKeepAwake)
                Button(presentationTitle, action: model.onTogglePresentationMode)
                Button("Hand Mirror", action: model.onOpenHandMirror)
                Button("Refresh Displays", action: model.onRefreshDisplays)
            }

            if !model.state.displays.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.state.displays) { display in
                        HStack {
                            Text(display.name)
                            Spacer()
                            Text(display.capabilitySummary)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var keepAwakeTitle: String {
        model.state.keepAwake == .running ? "Stop Awake" : "Keep Awake"
    }

    private var presentationTitle: String {
        model.state.presentationMode == .running ? "Stop Presenting" : "Presentation Mode"
    }
}

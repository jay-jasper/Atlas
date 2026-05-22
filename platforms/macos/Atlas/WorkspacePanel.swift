import SwiftUI

@MainActor
final class WorkspacePanelModel: ObservableObject {
    @Published private(set) var workspaces: [Workspace] = []
    @Published private(set) var restoreIssues: [WorkspaceRestoreIssue] = []
    @Published private(set) var statusMessage: String = ""

    private let store: WorkspaceStoring
    private let service: WorkspaceWindowService
    private let permissionChecker: WindowManagementPermissionChecking
    private let isFeatureEnabled: () -> Bool

    init(
        store: WorkspaceStoring,
        service: WorkspaceWindowService,
        permissionChecker: WindowManagementPermissionChecking,
        isFeatureEnabled: @escaping () -> Bool
    ) {
        self.store = store
        self.service = service
        self.permissionChecker = permissionChecker
        self.isFeatureEnabled = isFeatureEnabled
    }

    func reload() throws {
        workspaces = try store.load()
    }

    func saveCurrentLayout(named name: String) throws {
        guard isFeatureEnabled() else {
            statusMessage = "Window Manager is disabled"
            return
        }

        guard permissionChecker.isTrusted else {
            permissionChecker.requestPermission()
            statusMessage = "Accessibility permission is required"
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            statusMessage = "Workspace name is required"
            return
        }

        let workspace = try service.captureWorkspace(named: trimmedName)
        try store.save(workspace)
        restoreIssues = []
        try reload()
        statusMessage = "Saved \(workspace.windows.count) windows"
    }

    func restore(_ workspace: Workspace) throws {
        guard isFeatureEnabled() else {
            statusMessage = "Window Manager is disabled"
            return
        }

        guard permissionChecker.isTrusted else {
            permissionChecker.requestPermission()
            statusMessage = "Accessibility permission is required"
            return
        }

        let report = try service.restore(workspace)
        restoreIssues = report.issues
        statusMessage = "Restored \(report.restoredWindows.count) windows, \(report.issues.count) issue"
    }

    func delete(_ workspace: Workspace) throws {
        try store.delete(id: workspace.id)
        restoreIssues = []
        try reload()
        statusMessage = "Deleted \(workspace.name)"
    }
}

struct WorkspacePanel: View {
    @ObservedObject var model: WorkspacePanelModel
    @State private var workspaceName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Workspaces")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Save") {
                    try? model.saveCurrentLayout(named: workspaceName)
                    workspaceName = ""
                }
            }

            TextField("Workspace name", text: $workspaceName)

            ForEach(model.workspaces) { workspace in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workspace.name)
                        Text("\(workspace.windows.count) windows")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Restore") {
                        try? model.restore(workspace)
                    }
                    Button("Delete") {
                        try? model.delete(workspace)
                    }
                }
            }

            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(model.restoreIssues) { issue in
                Text(issue.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            try? model.reload()
        }
    }
}

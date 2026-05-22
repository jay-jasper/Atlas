import SwiftUI

struct AutomationSettingsView: View {
    private let store: CustomAutomationStoring

    @State private var commands: [CustomAutomationCommand] = []
    @State private var selectedID: UUID?
    @State private var title = ""
    @State private var command = ""
    @State private var kind: CustomAutomationKind = .shell
    @State private var keywords = ""
    @State private var timeoutSeconds = 10.0
    @State private var requiresConfirmation = true
    @State private var validationMessage: String?

    init(store: CustomAutomationStoring) {
        self.store = store
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Custom Automation")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Shell and Python automations can read files, modify files, and run local programs. Only save commands you trust.")
                .font(.caption)
                .foregroundColor(.orange)

            commandList
            editor
        }
        .onAppear(perform: reload)
    }

    private var commandList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if commands.isEmpty {
                Text("No custom automations saved.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(commands) { item in
                    HStack {
                        Button {
                            edit(item)
                        } label: {
                            Label(item.title, systemImage: item.kind == .python ? "curlybraces" : "terminal")
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button {
                            delete(item)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                }
            }

            Button("New Automation", action: clearDraft)
                .buttonStyle(.bordered)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Kind", selection: $kind) {
                ForEach(CustomAutomationKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            TextField("Title", text: $title)
            TextEditor(text: $command)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 70)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.25))
                )
            TextField("Keywords, comma separated", text: $keywords)

            HStack {
                Text("Timeout")
                TextField("Seconds", value: $timeoutSeconds, format: .number)
                    .frame(width: 70)
                Text("seconds")
                    .foregroundColor(.secondary)
            }

            Toggle("Require confirmation before running", isOn: $requiresConfirmation)

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Button("Save Automation", action: save)
                .buttonStyle(.borderedProminent)
        }
    }

    private func reload() {
        commands = store.commands()
    }

    private func edit(_ item: CustomAutomationCommand) {
        selectedID = item.id
        title = item.title
        command = item.command
        kind = item.kind
        keywords = item.keywords.joined(separator: ", ")
        timeoutSeconds = item.timeoutSeconds
        requiresConfirmation = item.requiresConfirmation
        validationMessage = nil
    }

    private func clearDraft() {
        selectedID = nil
        title = ""
        command = ""
        kind = .shell
        keywords = ""
        timeoutSeconds = 10
        requiresConfirmation = true
        validationMessage = nil
    }

    private func delete(_ item: CustomAutomationCommand) {
        do {
            try store.delete(id: item.id)
            reload()
            if selectedID == item.id {
                clearDraft()
            }
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func save() {
        let now = Date()
        let existing = selectedID.flatMap { id in commands.first { $0.id == id } }
        let draft = CustomAutomationCommand(
            id: existing?.id ?? UUID(),
            title: title,
            command: command,
            kind: kind,
            keywords: keywords.split(separator: ",").map(String.init),
            timeoutSeconds: timeoutSeconds,
            requiresConfirmation: requiresConfirmation,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )

        guard draft.isValid else {
            validationMessage = CustomAutomationStoreError.invalidCommand.localizedDescription
            return
        }

        do {
            try store.upsert(draft)
            reload()
            edit(draft)
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

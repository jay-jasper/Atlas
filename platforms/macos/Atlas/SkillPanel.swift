import SwiftUI

@MainActor
struct SkillPanel: View {
    let skill: SkillDefinition
    let runner: SkillRunner

    @State private var output = ""
    @State private var isRunning = false
    @State private var errorText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                Text(skill.title)
                    .font(.headline)
                Spacer()
            }

            if !skill.detail.isEmpty {
                Text(skill.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            permissionList

            Button {
                run()
            } label: {
                Label(isRunning ? "Running" : "Run", systemImage: "play.fill")
            }
            .disabled(isRunning)

            if !output.isEmpty {
                Text(output)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }

            if !errorText.isEmpty {
                Text(errorText)
                    .foregroundColor(.red)
            }
        }
        .padding()
    }

    private var permissionList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(skill.requiredPermissions, id: \.rawValue) { permission in
                Label(permission.title, systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func run() {
        isRunning = true
        errorText = ""
        output = ""

        Task {
            do {
                let result = try await runner.run(skill)
                output = result.output
            } catch {
                errorText = error.localizedDescription
            }
            isRunning = false
        }
    }
}

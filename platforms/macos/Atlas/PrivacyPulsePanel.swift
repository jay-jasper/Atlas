import SwiftUI

struct PrivacyPulseStatusRowState: Equatable {
    let category: PrivacyPulseCategory
    let label: String
}

struct PrivacyPulseEventRowState: Equatable {
    let title: String
    let category: String
    let detail: String
}

struct PrivacyPulsePanelState: Equatable {
    let snapshot: PrivacyPulseSnapshot

    var statusRows: [PrivacyPulseStatusRowState] {
        PrivacyPulseCategory.allCases.map { category in
            PrivacyPulseStatusRowState(category: category, label: snapshot.status(for: category).label)
        }
    }

    var eventRows: [PrivacyPulseEventRowState] {
        snapshot.events.map { event in
            PrivacyPulseEventRowState(
                title: event.title,
                category: event.category.title,
                detail: event.detail
            )
        }
    }

    var emptyText: String? {
        snapshot.events.isEmpty ? "No Atlas privacy access recorded." : nil
    }
}

struct PrivacyPulsePanel: View {
    let snapshot: PrivacyPulseSnapshot
    let onRefresh: () -> Void
    private var state: PrivacyPulsePanelState {
        PrivacyPulsePanelState(snapshot: snapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Privacy Pulse")
                    .font(.headline)
                Spacer()
                Button("Refresh", action: onRefresh)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(state.statusRows, id: \.category) { row in
                    PrivacyPulseStatusRow(
                        category: row.category,
                        statusLabel: row.label,
                        status: snapshot.status(for: row.category)
                    )
                }
            }

            Divider()

            Text("Recent Atlas Access")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if let emptyText = state.emptyText {
                Text(emptyText)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(snapshot.events) { event in
                    PrivacyPulseEventRow(event: event)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PrivacyPulseStatusRow: View {
    let category: PrivacyPulseCategory
    let statusLabel: String
    let status: PrivacyPulseStatus

    var body: some View {
        HStack {
            Image(systemName: iconName)
                .frame(width: 18)
            Text(category.title)
            Spacer()
            Text(statusLabel)
                .foregroundColor(statusColor)
        }
        .font(.subheadline)
    }

    private var iconName: String {
        switch category {
        case .camera:
            return "camera"
        case .microphone:
            return "mic"
        case .clipboard:
            return "doc.on.clipboard"
        case .screenRecording:
            return "rectangle.dashed"
        case .accessibility:
            return "accessibility"
        }
    }

    private var statusColor: Color {
        switch status {
        case .allowed, .recentlyUsed:
            return .green
        case .denied:
            return .red
        case .notDetermined, .inactive:
            return .secondary
        }
    }
}

private struct PrivacyPulseEventRow: View {
    let event: PrivacyPulseEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(event.title)
                    .font(.subheadline)
                Spacer()
                Text(event.category.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(event.detail)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

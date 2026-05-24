import SwiftUI

struct CalendarPanel: View {
    @ObservedObject var service: CalendarService

    private var groupedEvents: [(String, [CalendarEvent])] {
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        var groups: [(String, [CalendarEvent])] = []
        var seen: Set<String> = []
        for event in service.events {
            let label: String
            if cal.isDateInToday(event.startDate) {
                label = "Today"
            } else if cal.isDateInTomorrow(event.startDate) {
                label = "Tomorrow"
            } else {
                label = formatter.string(from: event.startDate)
            }
            if !seen.contains(label) {
                seen.insert(label)
                groups.append((label, []))
            }
            if let idx = groups.firstIndex(where: { $0.0 == label }) {
                groups[idx].1.append(event)
            }
        }
        return groups
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Calendar", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                Button {
                    service.fetchEvents()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh events")
            }

            switch service.authorizationStatus {
            case .notDetermined:
                Button("Grant Calendar Access") {
                    service.requestAccessIfNeeded()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

            case .denied, .restricted:
                Text("Calendar access is denied. Enable it in System Settings → Privacy → Calendars.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            default:
                if groupedEvents.isEmpty {
                    Text(service.statusMessage.isEmpty ? "No upcoming events" : service.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(groupedEvents, id: \.0) { label, events in
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(events) { event in
                            CalendarEventRow(event: event)
                        }
                    }
                }
            }
        }
        .padding()
        .onAppear { service.requestAccessIfNeeded() }
    }
}

private struct CalendarEventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.calendarColor)
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(event.timeRange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let loc = event.location {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(loc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if event.isNow {
                Text("Now")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

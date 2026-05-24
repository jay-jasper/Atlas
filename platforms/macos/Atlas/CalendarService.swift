import EventKit
import Foundation
import SwiftUI

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarColor: Color
    let location: String?

    var timeRange: String {
        if isAllDay { return "All day" }
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        fmt.dateStyle = .none
        return "\(fmt.string(from: startDate)) – \(fmt.string(from: endDate))"
    }

    var isNow: Bool {
        let now = Date()
        return startDate <= now && endDate >= now
    }

    var startsToday: Bool {
        Calendar.current.isDateInToday(startDate)
    }
}

@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published private(set) var statusMessage: String = ""

    private let store: EKEventStore
    private let lookaheadDays: Int

    init(store: EKEventStore = EKEventStore(), lookaheadDays: Int = 7) {
        self.store = store
        self.lookaheadDays = lookaheadDays
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    func requestAccessIfNeeded() {
        let current = EKEventStore.authorizationStatus(for: .event)
        authorizationStatus = current
        guard current == .notDetermined else {
            if current == .authorized { fetchEvents() }
            return
        }
        store.requestAccess(to: .event) { [weak self] granted, _ in
            Task { @MainActor [weak self] in
                self?.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
                if granted { self?.fetchEvents() }
            }
        }
    }

    func fetchEvents() {
        guard authorizationStatus == .authorized else {
            statusMessage = authorizationStatus == .denied ? "Calendar access denied" : "Calendar access required"
            return
        }

        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: lookaheadDays, to: start) ?? start
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let ekEvents = store.events(matching: pred)

        events = ekEvents
            .sorted { $0.startDate < $1.startDate }
            .map { ek in
                CalendarEvent(
                    id: ek.eventIdentifier ?? UUID().uuidString,
                    title: ek.title ?? "Untitled",
                    startDate: ek.startDate,
                    endDate: ek.endDate,
                    isAllDay: ek.isAllDay,
                    calendarColor: Color(nsColor: NSColor(cgColor: ek.calendar.cgColor) ?? .systemBlue),
                    location: ek.location?.isEmpty == false ? ek.location : nil
                )
            }
        statusMessage = events.isEmpty ? "No upcoming events" : ""
    }
}

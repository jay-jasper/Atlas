import AppKit
import EventKit
import Foundation

/// 会议链接识别(纯逻辑,可测)。
enum MeetingLinkDetector {
    private static let patterns = [
        #"https://[\w.-]*zoom\.us/j/[\w?=&-]+"#,
        #"https://meet\.google\.com/[\w-]+"#,
        #"https://teams\.microsoft\.com/l/meetup-join/[^\s>"']+"#,
        #"https://[\w.-]*webex\.com/[^\s>"']+"#,
        #"https://[\w.-]*feishu\.cn/j/[\w-]+"#,
        #"https://meeting\.tencent\.com/dm/[\w-]+"#,
    ]

    static func firstLink(in text: String?) -> URL? {
        guard let text, !text.isEmpty else { return nil }
        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                return URL(string: String(text[range]))
            }
        }
        return nil
    }
}

/// EventKit 事件搜索:未来 7 天,标题命中;会议链接一键加入。
final class CalendarEventsProvider: CommandProviding {
    private let eventsLookup: (String) -> [(title: String, start: Date, meeting: URL?, eventID: String)]
    private let open: (URL) -> Void

    /// 生产构造:真 EKEventStore(权限已授时才有结果)。
    convenience init() {
        let store = EKEventStore()
        self.init(
            eventsLookup: { query in
                guard ToolPermission.calendar.isGranted else { return [] }
                let start = Date()
                let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
                let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
                let events = store.events(matching: predicate)
                let needle = query.lowercased()
                return events
                    .filter { needle.isEmpty || $0.title?.lowercased().contains(needle) == true }
                    .prefix(8)
                    .map { event in
                        let meetingText = [event.notes, event.location, event.url?.absoluteString]
                            .compactMap { $0 }
                            .joined(separator: "\n")
                        return (
                            title: event.title ?? "(无标题)",
                            start: event.startDate,
                            meeting: event.url.flatMap { MeetingLinkDetector.firstLink(in: $0.absoluteString) }
                                ?? MeetingLinkDetector.firstLink(in: meetingText),
                            eventID: event.eventIdentifier ?? UUID().uuidString
                        )
                    }
            },
            open: { NSWorkspace.shared.open($0) }
        )
    }

    init(
        eventsLookup: @escaping (String) -> [(title: String, start: Date, meeting: URL?, eventID: String)],
        open: @escaping (URL) -> Void
    ) {
        self.eventsLookup = eventsLookup
        self.open = open
    }

    func results(for query: String) -> [PaletteCommand] {
        let q = query.trimmingCharacters(in: .whitespaces)
        // 空查询显示"今日日程"入口;有查询直接搜事件。
        let events = eventsLookup(q)
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        let isChineseUI = AppLanguage.current == .zh

        return events.map { event in
            let hasMeeting = event.meeting != nil
            return PaletteCommand(
                id: UUID(),
                title: event.title,
                subtitle: formatter.string(from: event.start)
                    + (hasMeeting ? (isChineseUI ? " · 可加入会议" : " · Join available") : ""),
                icon: .sfSymbol(hasMeeting ? "video" : "calendar"),
                keywords: ["calendar", "日历", "日程", "会议", "richeng", event.title],
                action: .execute { [open] in
                    if let meeting = event.meeting {
                        open(meeting)
                    } else if let url = URL(string: "ical://ekevent/\(event.eventID)") {
                        open(url)
                    }
                },
                category: isChineseUI ? "日历" : "Calendar"
            )
        }
    }
}

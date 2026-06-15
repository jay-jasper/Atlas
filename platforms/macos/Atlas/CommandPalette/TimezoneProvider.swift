import Foundation

/// Converts a time across timezones: `9am PST in Tokyo`, `15:00 UTC in PST`.
/// Recognizes common abbreviations and city names. Copies the result on select.
final class TimezoneProvider: CommandProviding {
    private let copy: PasteboardWriting
    private let referenceDate: Date

    init(copy: @escaping PasteboardWriting = Pasteboard.system, referenceDate: Date = Date()) {
        self.copy = copy
        self.referenceDate = referenceDate
    }

    private static let zoneAliases: [String: String] = [
        "pst": "America/Los_Angeles", "pdt": "America/Los_Angeles", "pt": "America/Los_Angeles",
        "est": "America/New_York", "edt": "America/New_York", "et": "America/New_York",
        "cst": "America/Chicago", "ct": "America/Chicago",
        "mst": "America/Denver", "mt": "America/Denver",
        "utc": "UTC", "gmt": "GMT",
        "cet": "Europe/Paris", "bst": "Europe/London", "london": "Europe/London",
        "tokyo": "Asia/Tokyo", "jst": "Asia/Tokyo",
        "beijing": "Asia/Shanghai", "shanghai": "Asia/Shanghai", "cn": "Asia/Shanghai",
        "ist": "Asia/Kolkata", "india": "Asia/Kolkata",
        "sydney": "Australia/Sydney", "aest": "Australia/Sydney",
        "berlin": "Europe/Berlin", "paris": "Europe/Paris", "newyork": "America/New_York",
    ]

    func results(for query: String) -> [PaletteCommand] {
        let lower = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // <time> <fromzone> in <tozone>
        let segments = lower.components(separatedBy: " in ")
        guard segments.count == 2 else { return [] }
        let target = segments[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
        guard let toZone = Self.zone(for: target) else { return [] }

        let leftParts = segments[0].split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard leftParts.count >= 2,
              let (hour, minute) = Self.parseTime(leftParts[0]),
              let fromZone = Self.zone(for: leftParts[1]) else {
            return []
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = fromZone
        let components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        var dc = DateComponents()
        dc.year = components.year; dc.month = components.month; dc.day = components.day
        dc.hour = hour; dc.minute = minute
        guard let date = calendar.date(from: dc) else { return [] }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = toZone
        formatter.dateFormat = "h:mm a"
        let value = formatter.string(from: date)

        return [PaletteCommand(
            id: UUID(),
            title: "\(value) \(toZone.abbreviation() ?? target.uppercased())",
            subtitle: "\(leftParts[0]) \(leftParts[1].uppercased()) → \(target.uppercased()) · ↵ to copy",
            icon: .sfSymbol("clock"),
            keywords: ["timezone", "time", "convert", "tz"],
            action: .execute { [copy] in copy(value) },
            category: "Time"
        )]
    }

    static func zone(for name: String) -> TimeZone? {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        if let identifier = zoneAliases[key] { return TimeZone(identifier: identifier) }
        return TimeZone(abbreviation: name.uppercased()) ?? TimeZone(identifier: name)
    }

    /// Parses `9am`, `9:30pm`, `15:00`, `15` into (hour, minute) in 24h.
    static func parseTime(_ raw: String) -> (Int, Int)? {
        var text = raw.lowercased()
        var isPM = false
        var isAM = false
        if text.hasSuffix("am") { isAM = true; text.removeLast(2) }
        else if text.hasSuffix("pm") { isPM = true; text.removeLast(2) }

        let pieces = text.split(separator: ":").map(String.init)
        guard let hourRaw = pieces.first, var hour = Int(hourRaw) else { return nil }
        let minute = pieces.count > 1 ? (Int(pieces[1]) ?? 0) : 0
        if isPM && hour < 12 { hour += 12 }
        if isAM && hour == 12 { hour = 0 }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }
}

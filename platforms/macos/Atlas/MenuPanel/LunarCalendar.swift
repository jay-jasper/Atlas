import Foundation

/// Chinese-lunar day labels for the calendar widget.
enum LunarCalendar {
    private static let dayNames = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十",
    ]

    private static let monthNames = [
        "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月",
    ]

    /// Lunar label for a date: the first day of a lunar month shows the month
    /// name ("五月"), every other day shows the day name ("廿八").
    static func dayLabel(for date: Date) -> String {
        var calendar = Calendar(identifier: .chinese)
        calendar.timeZone = TimeZone.current
        let components = calendar.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day,
              day >= 1, day <= dayNames.count, month >= 1, month <= monthNames.count else {
            return ""
        }
        if day == 1 {
            return monthNames[month - 1]
        }
        return dayNames[day - 1]
    }
}

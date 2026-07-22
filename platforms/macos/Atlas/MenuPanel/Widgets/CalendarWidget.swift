import SwiftUI

/// 月历 + 农历,今天高亮,左右切月。自包含,无外部数据。
struct CalendarWidget: View {
    @State private var displayedMonth: Date = Date()

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 6) {
            header
            weekdayRow
            dayGrid
        }
        .glassCard(padding: 10)
    }

    private var header: some View {
        HStack {
            Text(monthTitle)
                .font(.callout.weight(.semibold))
            Spacer()
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left").font(.caption)
            }
            .buttonStyle(.plain)
            Button("今天") {
                displayedMonth = Date()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.accentColor)
            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right").font(.caption)
            }
            .buttonStyle(.plain)
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy 年 MM 月"
        return formatter.string(from: displayedMonth)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { name in
                Text(name)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dayGrid: some View {
        let days = gridDays()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
            ForEach(days, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)
        VStack(spacing: 0) {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 12, weight: isToday ? .bold : .regular))
            Text(LunarCalendar.dayLabel(for: day))
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 30)
        .opacity(inMonth ? 1 : 0.3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isToday ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .focusable(false)
    }

    private func shiftMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = next
        }
    }

    /// 6 weeks × 7 days covering the displayed month, starting on Sunday.
    private func gridDays() -> [Date] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) else {
            return []
        }
        let weekday = calendar.component(.weekday, from: monthStart) // 1 = Sunday
        guard let gridStart = calendar.date(byAdding: .day, value: -(weekday - 1), to: monthStart) else {
            return []
        }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }
}

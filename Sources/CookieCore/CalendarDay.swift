import Foundation

/// A calendar date with no time or time zone. Tasks are assigned to one of
/// these, never to a `Date`, so an assignment can't drift across midnight
/// when converted through UTC.
public struct CalendarDay: Hashable, Comparable, Codable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    public static func today(calendar: Calendar = .current) -> CalendarDay {
        CalendarDay(Date.now, calendar: calendar)
    }

    /// Midnight at the start of this day in the given calendar.
    public func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public func adding(days: Int, calendar: Calendar = .current) -> CalendarDay {
        CalendarDay(calendar.date(byAdding: .day, value: days, to: date(in: calendar))!, calendar: calendar)
    }

    public var calendarMonth: CalendarMonth {
        CalendarMonth(year: year, month: month)
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// A year and month, used for the displayed calendar page.
public struct CalendarMonth: Hashable, Comparable, Codable, Sendable {
    public var year: Int
    public var month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public init(containing day: CalendarDay) {
        self.init(year: day.year, month: day.month)
    }

    public var firstDay: CalendarDay {
        CalendarDay(year: year, month: month, day: 1)
    }

    public func adding(months: Int, calendar: Calendar = .current) -> CalendarMonth {
        let date = calendar.date(byAdding: .month, value: months, to: firstDay.date(in: calendar))!
        return CalendarDay(date, calendar: calendar).calendarMonth
    }

    public func contains(_ day: CalendarDay) -> Bool {
        day.year == year && day.month == month
    }

    /// The 42 days shown in a fixed six-row month grid: the week containing
    /// the first of the month through the end of the sixth row, honoring the
    /// calendar's first weekday. Leading and trailing days belong to the
    /// adjacent months.
    public func gridDays(calendar: Calendar = .current) -> [CalendarDay] {
        let first = firstDay.date(in: calendar)
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let start = firstDay.adding(days: -leading, calendar: calendar)
        return (0..<42).map { start.adding(days: $0, calendar: calendar) }
    }

    public static func < (lhs: CalendarMonth, rhs: CalendarMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

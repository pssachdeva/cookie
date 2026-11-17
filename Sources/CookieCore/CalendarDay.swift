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

    public init(_ date: Date, calendar: Calendar = .planner) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    public static func today(calendar: Calendar = .planner) -> CalendarDay {
        CalendarDay(Date.now, calendar: calendar)
    }

    /// Midnight at the start of this day in the given calendar.
    public func date(in calendar: Calendar = .planner) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public func adding(days: Int, calendar: Calendar = .planner) -> CalendarDay {
        CalendarDay(calendar.date(byAdding: .day, value: days, to: date(in: calendar))!, calendar: calendar)
    }

    public var calendarMonth: CalendarMonth {
        CalendarMonth(year: year, month: month)
    }

    /// Whether this is a date that exists: February 30 and month 13 don't.
    public var isRealDate: Bool {
        guard year >= 1, (1...12).contains(month), (1...31).contains(day) else { return false }
        let calendar = Calendar.planner
        return CalendarDay(date(in: calendar), calendar: calendar) == self
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension Calendar {
    /// The calendar all day math runs on: Gregorian, whatever calendar the
    /// device is set to, in the current time zone and with the person's
    /// first day of the week. A task's day is saved and synced as a
    /// Gregorian year, month, and day; read through a device's Buddhist or
    /// Hebrew calendar, today would be written with that calendar's year
    /// and month and land centuries away on every other device.
    public static var planner: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        calendar.timeZone = .current
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
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

    public func adding(months: Int, calendar: Calendar = .planner) -> CalendarMonth {
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
    public func gridDays(calendar: Calendar = .planner) -> [CalendarDay] {
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

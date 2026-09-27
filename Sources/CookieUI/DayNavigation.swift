import SwiftUI
import CookieCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Per-window navigation state: the selected day and the displayed month are
/// interface state, independent of the task data.
@MainActor
@Observable
public final class DayNavigation {
    public private(set) var selectedDay: CalendarDay
    public private(set) var displayedMonth: CalendarMonth
    /// The current date, kept observable so the calendar, the day list, and
    /// the entry bar all move on at midnight without waiting for a redraw.
    public private(set) var today: CalendarDay
    /// Direction of the most recent change, used to pick slide edges.
    private(set) var dayDirection: Direction = .forward
    private(set) var monthDirection: Direction = .forward

    enum Direction { case forward, backward }

    public init(today: CalendarDay = .today()) {
        self.today = today
        selectedDay = today
        displayedMonth = today.calendarMonth
        // Midnight, waking from sleep past midnight, and clock or time zone
        // changes can all change the date. Coming back to the front is a
        // backstop in case a notification was missed.
        let center = NotificationCenter.default
        var names: [(NotificationCenter, Notification.Name)] = [
            (center, .NSCalendarDayChanged),
            (center, .NSSystemClockDidChange),
            (center, .NSSystemTimeZoneDidChange),
        ]
        #if os(macOS)
        names += [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
            (center, NSApplication.didBecomeActiveNotification),
        ]
        #else
        names += [
            (center, UIApplication.significantTimeChangeNotification),
            (center, UIApplication.didBecomeActiveNotification),
        ]
        #endif
        for (center, name) in names {
            _ = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshToday() }
            }
        }
    }

    /// Moves `today` on. A window left on today follows it to the new day;
    /// one showing another day stays put, so a day being worked on is never
    /// yanked away.
    public func refreshToday() {
        let now = CalendarDay.today()
        guard now != today else { return }
        let wasOnToday = selectedDay == today
        today = now
        if wasOnToday {
            withAnimation(.smooth(duration: 0.3)) { select(now) }
        }
    }

    public func select(_ day: CalendarDay) {
        guard day != selectedDay else { return }
        dayDirection = day > selectedDay ? .forward : .backward
        selectedDay = day
        showMonth(day.calendarMonth)
    }

    /// Browsing months changes only the displayed page, not the selection.
    public func showMonth(_ month: CalendarMonth) {
        guard month != displayedMonth else { return }
        monthDirection = month > displayedMonth ? .forward : .backward
        displayedMonth = month
    }

    public func goToToday() {
        refreshToday()
        select(today)
        showMonth(today.calendarMonth)
    }
}

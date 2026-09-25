import SwiftUI
import CookieCore

/// Per-window navigation state: the selected day and the displayed month are
/// interface state, independent of the task data.
@MainActor
@Observable
final class DayNavigation {
    private(set) var selectedDay: CalendarDay
    private(set) var displayedMonth: CalendarMonth
    /// The current date, kept observable so the calendar, the day list, and
    /// the entry bar all move on at midnight without waiting for a redraw.
    private(set) var today: CalendarDay
    /// Direction of the most recent change, used to pick slide edges.
    private(set) var dayDirection: Direction = .forward
    private(set) var monthDirection: Direction = .forward

    enum Direction { case forward, backward }

    init(today: CalendarDay = .today()) {
        self.today = today
        selectedDay = today
        displayedMonth = today.calendarMonth
        // Midnight, waking from sleep past midnight, and clock or time zone
        // changes can all change the date.
        let center = NotificationCenter.default
        let names: [(NotificationCenter, Notification.Name)] = [
            (center, .NSCalendarDayChanged),
            (center, .NSSystemClockDidChange),
            (center, .NSSystemTimeZoneDidChange),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
            // Backstop in case a notification was missed.
            (center, NSApplication.didBecomeActiveNotification),
        ]
        for (center, name) in names {
            _ = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshToday() }
            }
        }
    }

    /// Moves `today` on. A window left on today follows it to the new day;
    /// one showing another day stays put, so a day being worked on is never
    /// yanked away.
    func refreshToday() {
        let now = CalendarDay.today()
        guard now != today else { return }
        let wasOnToday = selectedDay == today
        today = now
        if wasOnToday {
            withAnimation(.smooth(duration: 0.3)) { select(now) }
        }
    }

    func select(_ day: CalendarDay) {
        guard day != selectedDay else { return }
        dayDirection = day > selectedDay ? .forward : .backward
        selectedDay = day
        showMonth(day.calendarMonth)
    }

    /// Browsing months changes only the displayed page, not the selection.
    func showMonth(_ month: CalendarMonth) {
        guard month != displayedMonth else { return }
        monthDirection = month > displayedMonth ? .forward : .backward
        displayedMonth = month
    }

    func goToToday() {
        refreshToday()
        select(today)
        showMonth(today.calendarMonth)
    }
}

/// Name of the coordinate space shared by the drag gesture, the frame
/// reports, and the drag overlay.
let windowSpace = "window"

struct MainWindowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigation: DayNavigation
    @State private var drag: DragController
    @State private var draft = ""

    init(store: TaskStore) {
        let navigation = DayNavigation()
        _navigation = State(initialValue: navigation)
        _drag = State(initialValue: DragController(navigation: navigation, store: store))
    }

    var body: some View {
        VStack(spacing: 0) {
            // The calendar sits on its own faintly tinted surface, running up
            // under the traffic lights, so it reads as a separate zone from
            // the list without a rule between them.
            CalendarView(navigation: navigation)
                .padding(.horizontal, 10)
                .background(Color.calendarSurface)

            EntryBar(draft: $draft, day: navigation.selectedDay)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            DayListView(day: navigation.selectedDay)
                .id(navigation.selectedDay)
                .transition(dayTransition)
        }
        .clipped()
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: navigation.selectedDay)
        .overlay { DragOverlay(drag: drag) }
        .animation(.easeOut(duration: 0.15), value: drag.isDragging)
        .coordinateSpace(name: windowSpace)
        .environment(drag)
        .environment(navigation)
        .frame(minWidth: Self.minSize.width, idealWidth: 360, minHeight: Self.minSize.height, idealHeight: 680)
        .background(.background)
        .background(WindowSizeLimits(min: Self.minSize, max: Self.maxSize, initial: Self.defaultSize))
        // Content starts at the window's top edge; the calendar header
        // shares the title bar's row with the traffic lights. Last in the
        // chain so `.clipped()` above clips to the full window, not to the
        // area below the title bar.
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Height of the hidden title bar's row, where the calendar header sits.
    static let titleBarHeight: CGFloat = 28
    /// Leading space the calendar header leaves for the traffic lights,
    /// measured from the calendar's own 10 pt inset.
    static let trafficLightInset: CGFloat = 58

    static let minSize = CGSize(width: 320, height: 560)
    static let defaultSize = CGSize(width: 360, height: 680)
    /// Width is capped so the window can't grow past the layout; height is
    /// free so a long list can have more room.
    static let maxSize = CGSize(width: 440, height: 4000)

    /// The outgoing list fades; the incoming one fades in with a small drift
    /// in the direction of travel. No full-height slide.
    private var dayTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let forward = navigation.dayDirection == .forward
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: forward ? 10 : -10)),
            removal: .opacity
        )
    }
}

/// Applies content size limits to the hosting NSWindow, and the default size
/// on a first launch. SwiftUI's `windowResizability(.contentSize)` was
/// unreliable with a flexible frame (it opened the window at the minimum
/// width), and macOS's per-app window placement memory can reopen the window
/// at a stale size even when the app has no saved frame of its own, so both
/// are handled on the window directly.
struct WindowSizeLimits: NSViewRepresentable {
    let min: CGSize
    let max: CGSize
    let initial: CGSize

    func makeNSView(context: Context) -> LimitView {
        let view = LimitView()
        view.limits = (min, max)
        view.initial = initial
        return view
    }

    func updateNSView(_ view: LimitView, context: Context) {
        view.limits = (min, max)
        view.initial = initial
    }

    final class LimitView: NSView {
        var limits: (CGSize, CGSize) = (.zero, .zero)
        var initial: CGSize = .zero
        private var applied = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Deferred: applying limits while the window is still being set
            // up clamps its placeholder frame before SwiftUI sizes it.
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        private func apply() {
            guard !applied, let window, window.isVisible else { return }
            applied = true
            window.contentMinSize = limits.0
            window.contentMaxSize = limits.1
            // SwiftUI stores the frame under this key once the user has
            // used the window; absent that, enforce the default size.
            if UserDefaults.standard.string(forKey: "NSWindow Frame \(window.identifier?.rawValue ?? "main")") == nil {
                window.setContentSize(initial)
            }
        }
    }
}

extension View {
    /// Reports this view's frame in the window coordinate space.
    func reportFrame(_ action: @escaping (CGRect) -> Void) -> some View {
        onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(windowSpace)) }, action: action)
    }
}

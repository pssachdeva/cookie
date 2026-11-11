import SwiftUI
import CookieCore

/// Name of the coordinate space shared by the drag, the frame reports, and
/// the drag overlay.
public let windowSpace = "window"

/// The app's main screen: the month calendar on its own tinted surface, the
/// entry field, and the selected day's checklist. The Mac window and the
/// iPhone app both show this.
public struct DayPlannerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigation: DayNavigation
    @State private var drag: DragController
    @State private var draft = ""

    public init(store: TaskStore) {
        let navigation = DayNavigation()
        _navigation = State(initialValue: navigation)
        _drag = State(initialValue: DragController(navigation: navigation, store: store))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // The calendar sits on its own faintly tinted surface, running up
            // to the top edge (under the Mac's traffic lights or the iPhone's
            // status bar), so it reads as a separate zone from the list
            // without a rule between them.
            CalendarView(navigation: navigation)
                .padding(.horizontal, 10)
                .background(Color.calendarSurface.ignoresSafeArea(edges: .top))

            EntryBar(draft: $draft, day: navigation.selectedDay)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            #if os(iOS)
            DayPager(navigation: navigation)
            #else
            DayListView(day: navigation.selectedDay)
                .id(navigation.selectedDay)
                .transition(dayTransition)
            #endif
        }
        .clipped()
        #if os(macOS)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: navigation.selectedDay)
        #endif
        .overlay { DragOverlay(drag: drag) }
        .animation(.easeOut(duration: 0.15), value: drag.isDragging)
        .coordinateSpace(name: windowSpace)
        #if os(iOS)
        // Touch drags use the system's drag and drop, which outlives the
        // row it started from when the list switches days. The whole screen
        // is the drop target, so locations arrive in the shared space.
        .onDrop(of: [.plainText], delegate: TaskDropDelegate(drag: drag))
        #endif
        .environment(drag)
        .environment(navigation)
        .background(.background)
    }

    #if os(macOS)
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
    #endif
}

#if os(iOS)
/// The day lists as side-by-side pages. Swiping drags the neighboring day
/// in with the finger, and letting go settles on whichever day is mostly
/// showing, with the system's own paging physics.
private struct DayPager: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let navigation: DayNavigation
    /// The day on page zero. Pages are numbered from it, so the scroll
    /// position is a plain index.
    @State private var anchor: CalendarDay
    /// The page under the center of the screen.
    @State private var position: Int?

    /// Pages either side of the anchor. Moving further re-anchors.
    private static let reach = 1000

    init(navigation: DayNavigation) {
        self.navigation = navigation
        _anchor = State(initialValue: navigation.selectedDay)
        _position = State(initialValue: 0)
    }

    var body: some View {
        // Pages are sized to exactly the space the pager has. Sizing them
        // from the scroll view as a container made them taller than the
        // pager on iOS 26, which centered them and pushed the day header up
        // under the entry bar.
        GeometryReader { proxy in
            pager(pageSize: proxy.size)
        }
        .clipped()
    }

    private func pager(pageSize: CGSize) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 0) {
                ForEach(-Self.reach...Self.reach, id: \.self) { offset in
                    let day = anchor.adding(days: offset)
                    // Equatable, so a new page size (every frame while the
                    // calendar folds) only lays the list out again rather
                    // than rebuilding all its rows.
                    DayPage(day: day, isCurrent: day == navigation.selectedDay)
                        .equatable()
                        .frame(width: pageSize.width, height: pageSize.height)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        // Centered, so the day changes once a page is more than halfway in.
        .scrollPosition(id: $position, anchor: .center)
        .onChange(of: position) { _, offset in
            guard let offset else { return }
            let day = anchor.adding(days: offset)
            guard day != navigation.selectedDay else { return }
            withAnimation(.smooth(duration: 0.3)) { navigation.select(day) }
        }
        // Days picked elsewhere (the calendar, the arrows, a drag): the next
        // or previous day slides in; anything further jumps straight there.
        .onChange(of: navigation.selectedDay) { _, day in
            let target = Self.days(from: anchor, to: day)
            if abs(target) > Self.reach - 10 {
                anchor = day
                position = 0
                return
            }
            guard target != position else { return }
            if let position, abs(target - position) == 1, !reduceMotion {
                withAnimation(.smooth(duration: 0.3)) { self.position = target }
            } else {
                position = target
            }
        }
    }

    private static func days(from start: CalendarDay, to end: CalendarDay) -> Int {
        Calendar.current.dateComponents([.day], from: start.date(), to: end.date()).day ?? 0
    }
}

/// One day's list in the pager.
private struct DayPage: View, Equatable {
    let day: CalendarDay
    /// Only the page showing feeds the drag its frames (a neighbor shares
    /// rows, like yesterday's unfinished tasks under today's Earlier).
    let isCurrent: Bool

    var body: some View {
        DayListView(day: day)
            .environment(\.isCurrentDayPage, isCurrent)
    }
}
#endif

/// Where the calendar header sits. The Mac puts it in the hidden title bar's
/// row, beside the traffic lights; the iPhone puts it under the status bar.
public struct CalendarHeaderMetrics: Sendable {
    /// Height of the header row.
    public var height: CGFloat
    /// Extra leading space, measured from the calendar's own 10 pt inset.
    public var leadingInset: CGFloat

    public init(height: CGFloat, leadingInset: CGFloat) {
        self.height = height
        self.leadingInset = leadingInset
    }
}

extension EnvironmentValues {
    @Entry public var calendarHeaderMetrics = CalendarHeaderMetrics(height: 44, leadingInset: 0)
}

extension View {
    /// Reports this view's frame in the window coordinate space.
    func reportFrame(_ action: @escaping (CGRect) -> Void) -> some View {
        onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(windowSpace)) }, action: action)
    }

    /// Marks this view as the previous or next arrow for a drag: resting a
    /// dragged task on it steps back or forward.
    public func dragArrowTarget(forward: Bool) -> some View {
        modifier(DragArrowTarget(forward: forward))
    }
}

private struct DragArrowTarget: ViewModifier {
    @Environment(DragController.self) private var drag
    let forward: Bool

    func body(content: Content) -> some View {
        content.reportFrame { frame in
            if forward { drag.nextMonthFrame = frame } else { drag.previousMonthFrame = frame }
        }
    }
}

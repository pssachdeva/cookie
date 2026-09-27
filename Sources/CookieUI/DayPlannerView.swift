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

            DayListView(day: navigation.selectedDay)
                .id(navigation.selectedDay)
                .transition(dayTransition)
        }
        .clipped()
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: navigation.selectedDay)
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
}

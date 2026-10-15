import SwiftUI
import CookieCore

struct CalendarView: View {
    @Environment(TaskStore.self) private var store
    @Environment(DragController.self) private var drag
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calendarHeaderMetrics) private var headerMetrics
    // withAnimation cannot animate an @AppStorage change (it arrives via
    // UserDefaults, outside the transaction), so the layout is driven by a
    // @State mirror and the stored value is written alongside it.
    @AppStorage("calendarCollapsed") private var storedCollapsed = false
    @State private var collapsed = false
    @Namespace private var selectionNamespace
    let navigation: DayNavigation

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            header
            // Everything below the header folds away, including the resize
            // handle and the gap under the header, so collapsing leaves only
            // the header row on the calendar surface.
            VStack(spacing: 0) {
                #if os(iOS)
                // Swipe the grid sideways to change months. The gesture
                // needs clear horizontal travel, so taps on days are
                // untouched, and it sits on the container so it survives
                // the grid being replaced by the month transition.
                monthArea
                    .gesture(
                        DragGesture(minimumDistance: 24)
                            .onEnded { value in
                                let dx = value.translation.width
                                let dy = value.translation.height
                                guard abs(dx) > 50, abs(dx) > abs(dy) * 1.5 else { return }
                                shift(by: dx < 0 ? 1 : -1)
                            }
                    )
                    .padding(.bottom, 8)
                #else
                monthArea
                CalendarSizeHandle()
                    .padding(.top, 2)
                #endif
            }
            .padding(.top, 10)
            // Fold as a drawer: the container's height animates to zero and
            // clips the grid, which is anchored at the bottom, so it slides up
            // and tucks under the header's lower edge rather than passing
            // through it. A layout rather than a measured frame, so resizing
            // the rows doesn't lag a frame behind and jitter.
            .modifier(DrawerFold(openFraction: collapsed ? 0 : 1))
            .opacity(collapsed ? 0 : 1)
            .allowsHitTesting(!collapsed)
            .accessibilityHidden(collapsed)
        }
        .onAppear { collapsed = storedCollapsed }
        // Hidden cells must stop being drop targets.
        .onChange(of: collapsed) { _, isCollapsed in if isCollapsed { drag.cellFrames = [:] } }
    }

    /// Weekday letters and the month grid, with the month slide.
    private var monthArea: some View {
        VStack(spacing: 6) {
            weekdayRow
            MonthGridView(
                month: navigation.displayedMonth,
                selected: navigation.selectedDay,
                today: navigation.today,
                unfinished: store.daysWithUnfinished(in: navigation.displayedMonth),
                selectionNamespace: selectionNamespace,
                onSelect: { day in withAnimation(.smooth(duration: 0.3)) { navigation.select(day) } }
            )
            .id(navigation.displayedMonth)
            .transition(monthTransition)
            .clipped()
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: navigation.displayedMonth)
        }
    }

    private var header: some View {
        HStack(spacing: 2) {
            // Collapse toggle: the chevron beside the month title.
            Button {
                // withAnimation, not a scoped .animation modifier, so the
                // parent layout (entry bar, list) moves in the same
                // transaction as the fold instead of jumping ahead of it.
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { collapsed.toggle() }
                storedCollapsed = collapsed
            } label: {
                HStack(spacing: 6) {
                    Text(monthTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.numericText())
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                }
                .contentShape(Rectangle())
            }
            // Ahead of the drag area, which would otherwise split the width.
            .layoutPriority(1)
            .help(collapsed ? "Show calendar" : "Hide calendar")
            .keyboardShortcut("c", modifiers: [.command, .shift])
            // On the Mac the header shares the hidden title bar's row, so its
            // empty stretch has to move the window like a title bar would.
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 24)
                .contentShape(Rectangle())
                #if os(macOS)
                .gesture(WindowDragGesture())
                #endif
            Button("Today") { withAnimation(.smooth(duration: 0.3)) { navigation.goToToday() } }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.cookieAccent)
                .fixedSize()
                .keyboardShortcut("t", modifiers: .command)
            Button { shift(by: -1) } label: {
                Image(systemName: "chevron.left").font(.body.weight(.medium))
            }
            .help(collapsed ? "Previous day" : "Previous month")
            .reportFrame { drag.previousMonthFrame = $0 }
            Button { shift(by: 1) } label: {
                Image(systemName: "chevron.right").font(.body.weight(.medium))
            }
            .help(collapsed ? "Next day" : "Next month")
            .reportFrame { drag.nextMonthFrame = $0 }
        }
        .buttonStyle(HeaderButtonStyle())
        .foregroundStyle(.secondary)
        // On the Mac, clear the traffic lights, which sit on this row.
        .padding(.leading, headerMetrics.leadingInset)
        .frame(height: headerMetrics.height)
    }

    private var weekdayRow: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let ordered = (0..<7).map { symbols[($0 + calendar.firstWeekday - 1) % 7] }
        return HStack(spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Expanded: the displayed month. Collapsed: the selected day's month,
    /// since there is no separate page to browse.
    private var monthTitle: String {
        let month = collapsed ? navigation.selectedDay.calendarMonth : navigation.displayedMonth
        return month.firstDay.date().formatted(.dateTime.month(.wide).year())
    }

    private var monthTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let forward = navigation.monthDirection == .forward
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading),
            removal: .move(edge: forward ? .leading : .trailing)
        )
    }

    /// Arrows browse months when the grid is visible and step days when it
    /// is collapsed.
    private func shift(by amount: Int) {
        if collapsed {
            withAnimation(.smooth(duration: 0.3)) { navigation.select(navigation.selectedDay.adding(days: amount)) }
        } else {
            withAnimation(.smooth(duration: 0.35)) { navigation.showMonth(navigation.displayedMonth.adding(months: amount)) }
        }
    }
}

struct MonthGridView: View {
    @Environment(DragController.self) private var drag
    #if os(iOS)
    /// Fixed on the iPhone (no resize handle); tall enough to be a
    /// comfortable touch target.
    private let rowHeight: Double = 44
    #else
    @AppStorage(CalendarSizeHandle.key) private var rowHeight = CalendarSizeHandle.defaultRowHeight
    #endif
    let month: CalendarMonth
    let selected: CalendarDay
    let today: CalendarDay
    let unfinished: Set<CalendarDay>
    let selectionNamespace: Namespace.ID
    let onSelect: (CalendarDay) -> Void

    var body: some View {
        // Six fixed-height rows of seven expanding cells. Fixed height keeps
        // the calendar compact regardless of window height.
        let days = month.gridDays()
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(days[row * 7 ..< row * 7 + 7], id: \.self) { day in
                        // A real button so accessibility and keyboard
                        // activation work, not only pointer taps.
                        Button { onSelect(day) } label: {
                            DayCell(
                                day: day,
                                inMonth: month.contains(day),
                                isSelected: day == selected,
                                isToday: day == today,
                                hasUnfinished: unfinished.contains(day),
                                isPast: day < today,
                                selectionNamespace: selectionNamespace
                            )
                        }
                        .buttonStyle(.plain)
                        .reportFrame { drag.cellFrames[day] = $0 }
                    }
                }
                .frame(height: rowHeight)
            }
        }
    }
}

struct DayCell: View {
    let day: CalendarDay
    let inMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let hasUnfinished: Bool
    let isPast: Bool
    let selectionNamespace: Namespace.ID

    var body: some View {
        // The number is always centered in its mark, and the unfinished-task
        // dot lives in its own strip below, outside the mark, so days with
        // and without a dot look the same (as in Apple's Calendar).
        VStack(spacing: 0) {
            ZStack {
                // Today keeps a soft tint even when another day is selected,
                // so it stays findable at a glance.
                if isToday && !isSelected {
                    DayMark()
                        .fill(Color.cookieAccent.opacity(0.16))
                }
                // The selection mark is matched across cells, so it glides
                // from the old date to the new one within a month.
                if isSelected {
                    DayMark()
                        .fill(Color.cookieAccent)
                        .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                }
                Text("\(day.day)")
                    .font(.system(size: 13, weight: isToday || isSelected ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(numberColor)
            }
            .padding(.top, 1)
            .frame(maxHeight: .infinity)

            // Indicator for unfinished tasks: a shape, not only a color,
            // so it reads without color vision. Filled for past-due
            // days, hollow for planned future days.
            Circle()
                .strokeBorder(indicatorColor, lineWidth: 1.4)
                .background(Circle().fill(isPast ? indicatorColor : .clear))
                .frame(width: 5, height: 5)
                .opacity(hasUnfinished ? 1 : 0)
                .frame(height: Self.dotStrip)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .opacity(inMonth ? 1 : 0.3)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Height of the strip under the mark that holds the dot.
    private static let dotStrip: CGFloat = 9

    private var numberColor: Color {
        if isSelected { return .white }
        if isToday { return .cookieAccent }
        return .primary
    }

    /// The dot sits below the mark, on the plain background, so it never
    /// needs a selected variant.
    private var indicatorColor: Color {
        isPast ? .overdue : .secondary
    }

    private var accessibilityText: String {
        var parts = [day.date().formatted(.dateTime.weekday(.wide).month(.wide).day())]
        if isToday { parts.append("today") }
        if hasUnfinished { parts.append("has unfinished tasks") }
        return parts.joined(separator: ", ")
    }
}

/// Today and selection mark: the largest square that fits the cell, with
/// continuous corners in proportion to its size. Sized from the cell's
/// shorter side, so it keeps its shape at any window width or row height
/// instead of stretching into a wide rectangle.
struct DayMark: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let square = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        return RoundedRectangle(cornerRadius: side * 0.3, style: .continuous).path(in: square)
    }
}

/// Shows a fraction of its content's natural height, keeping the bottom
/// edge, so animating the fraction folds the content up like a drawer.
private struct DrawerFold: ViewModifier {
    let openFraction: CGFloat

    func body(content: Content) -> some View {
        DrawerLayout(openFraction: openFraction) { content }
            .clipped()
    }
}

private struct DrawerLayout: Layout {
    var openFraction: CGFloat

    var animatableData: CGFloat {
        get { openFraction }
        set { openFraction = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let natural = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: natural.width, height: natural.height * openFraction)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let natural = content.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        content.place(
            at: CGPoint(x: bounds.minX, y: bounds.maxY),
            anchor: .bottomLeading,
            proposal: ProposedViewSize(width: bounds.width, height: natural.height)
        )
    }
}

/// Grabber at the bottom of the calendar. Dragging it changes the
/// calendar's row height (persisted); double-clicking resets it. It folds
/// away with the grid when the calendar is collapsed.
struct CalendarSizeHandle: View {
    static let key = "calendarRowHeight"
    static let defaultRowHeight: Double = 34
    static let range: ClosedRange<Double> = 24...56
    /// How far either side of the default, per row, the drag sticks to it:
    /// 3 pt per row, about 18 pt of pointer travel.
    static let snapZone: Double = 3

    @AppStorage(Self.key) private var rowHeight = Self.defaultRowHeight
    @State private var startHeight: Double?
    @State private var hovering = false

    var body: some View {
        Capsule()
            .fill(hovering || startHeight != nil ? Color.secondary : Color.secondary.opacity(0.35))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: 14)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            #if os(macOS)
            // Managed by the system, so it holds steady when the handle
            // slips out from under the pointer mid-drag.
            .pointerStyle(.rowResize)
            #endif
            .gesture(
                // Measured in the window, not on the handle: the handle
                // moves as the calendar grows, and measuring against it fed
                // each resize back into the drag.
                DragGesture(minimumDistance: 1, coordinateSpace: .named(windowSpace))
                    .onChanged { value in
                        if startHeight == nil { startHeight = rowHeight }
                        // Six rows share the drag distance. Whole points, so
                        // sub-point mouse motion doesn't relayout the window.
                        let proposed = ((startHeight ?? rowHeight) + value.translation.height / 6).rounded()
                        var clamped = min(Self.range.upperBound, max(Self.range.lowerBound, proposed))
                        // The default size is a detent: the drag sticks to
                        // it for a few points either way, then moves on.
                        if abs(clamped - Self.defaultRowHeight) <= Self.snapZone {
                            clamped = Self.defaultRowHeight
                        }
                        guard clamped != rowHeight else { return }
                        #if os(macOS)
                        if clamped == Self.defaultRowHeight {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        }
                        #endif
                        rowHeight = clamped
                    }
                    .onEnded { _ in startHeight = nil }
            )
            .onTapGesture(count: 2) {
                withAnimation(.smooth(duration: 0.3)) { rowHeight = Self.defaultRowHeight }
            }
            .help("Drag to resize the calendar; double-click to reset")
            .accessibilityLabel("Calendar height")
            .accessibilityValue("\(Int(rowHeight)) points per row")
    }
}

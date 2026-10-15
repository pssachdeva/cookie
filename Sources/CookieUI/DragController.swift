import SwiftUI
import CookieCore
#if os(macOS)
import AppKit
#endif

/// Where a dragged task would land if released now.
enum DropTarget: Equatable {
    case calendar(CalendarDay)
    case list(CalendarDay, index: Int)
    case none
}

/// In-window drag of a task row. Views report their frames (in the "window"
/// coordinate space) here; the row's gesture feeds pointer locations; the
/// overlay reads the ghost position and insertion line.
///
/// This is a custom gesture rather than system drag-and-drop because the
/// list under the pointer has to change days while the drag continues:
/// resting on a calendar day shows that day's list, ready for the drop.
@MainActor
@Observable
public final class DragController {
    struct Session {
        let taskID: UUID
        let text: String
        let isCompleted: Bool
        let sourceDay: CalendarDay
        /// Pointer offset from the row's top-left at grab time, so the ghost
        /// stays under the pointer where it was picked up.
        let grabOffset: CGSize
        let width: CGFloat
        var location: CGPoint
        /// Touch drags use the system's own lifted preview, so the overlay
        /// draws no ghost for them.
        var showsGhost = true
    }

    static let cellDwell: TimeInterval = 0.35
    static let arrowDwell: TimeInterval = 0.5

    private(set) var session: Session?

    // Geometry reported by views, in the "window" coordinate space.
    var cellFrames: [CalendarDay: CGRect] = [:]
    var rowFrames: [UUID: CGRect] = [:]
    /// Active rows of the selected day, in list order.
    var activeRows: [UUID] = []
    var activeListFrame: CGRect = .zero
    var listFrame: CGRect = .zero
    var previousMonthFrame: CGRect = .zero
    var nextMonthFrame: CGRect = .zero

    // Hover state.
    private(set) var hoverKey: AnyHashable?

    @ObservationIgnored private var dwellTimer: Timer?
    #if os(macOS)
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var mouseMonitor: Any?
    #else
    /// A touch drag the system has lifted but the finger hasn't moved yet,
    /// with where the finger was first reported. It becomes the session
    /// once the finger travels, so a long press that only opens the context
    /// menu (and never drops anything, so never ends) leaves no dimmed row.
    @ObservationIgnored private var pendingTouch: Session?
    @ObservationIgnored private var pendingOrigin: CGPoint?
    #endif

    private let navigation: DayNavigation
    private let store: TaskStore

    public init(navigation: DayNavigation, store: TaskStore) {
        self.navigation = navigation
        self.store = store
    }

    var isDragging: Bool { session != nil }

    // MARK: Session

    #if os(macOS)
    /// Starts a drag from a row's gesture. From here on the drag follows the
    /// mouse itself rather than the row's gesture: resting on a calendar day
    /// swaps the list, which removes the row (and its gesture) mid-drag.
    func begin(task: TaskItem, rowFrame: CGRect, grabbedAt start: CGPoint, now location: CGPoint) {
        guard session == nil else { return }
        session = Session(
            taskID: task.id,
            text: task.text,
            isCompleted: task.isCompleted,
            sourceDay: task.day,
            grabOffset: CGSize(width: start.x - rowFrame.minX, height: start.y - rowFrame.minY),
            width: rowFrame.width,
            location: location
        )
        updateHover(at: location)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // Escape
            MainActor.assumeIsolated { self?.cancel() }
            return nil
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let location = Self.windowLocation(of: event) else { return }
                self.update(location: location)
                if event.type == .leftMouseUp { self.end() }
            }
            return event
        }
    }

    /// The event's position in the "window" coordinate space: points from
    /// the window's top-left, since the content runs under the title bar.
    private static func windowLocation(of event: NSEvent) -> CGPoint? {
        guard let window = event.window else { return nil }
        let point = event.locationInWindow
        return CGPoint(x: point.x, y: window.frame.height - point.y)
    }
    #else
    /// Readies a touch drag, when the system lifts a row. Positions then
    /// arrive from `TaskDropDelegate`, and the drag starts once they move.
    func beginTouch(task: TaskItem) {
        // A drag the system cut short (an incoming call, say) never
        // reported its end; clear it.
        reset()
        pendingTouch = Session(
            taskID: task.id,
            text: task.text,
            isCompleted: task.isCompleted,
            sourceDay: task.day,
            grabOffset: .zero,
            width: 0,
            location: .zero,
            showsGhost: false
        )
    }

    /// Whether a lifted row is waiting for the finger to move.
    var hasPendingTouch: Bool { pendingTouch != nil }

    /// Feeds a touch position; starts the pending drag once the finger has
    /// moved past a small slop.
    func updateTouch(location: CGPoint) {
        if session == nil, let pending = pendingTouch {
            guard let origin = pendingOrigin else {
                pendingOrigin = location
                return
            }
            guard hypot(location.x - origin.x, location.y - origin.y) > 6 else { return }
            session = pending
            pendingTouch = nil
            pendingOrigin = nil
        }
        update(location: location)
    }
    #endif

    func update(location: CGPoint) {
        guard session != nil else { return }
        session?.location = location
        updateHover(at: location)
    }

    func end() {
        defer { reset() }
        guard let session else { return }
        switch target {
        case .calendar(let day):
            store.move(session.taskID, to: day)
            withAnimation(.snappy(duration: 0.3)) { navigation.select(day) }
        case .list(let day, let index):
            if session.isCompleted {
                // Completed tasks keep their state; position is by completion time.
                store.move(session.taskID, to: day)
            } else {
                store.move(session.taskID, to: day, at: index)
            }
        case .none:
            break
        }
    }

    func cancel() {
        reset()
    }

    // MARK: Targets

    var target: DropTarget {
        guard let session else { return .none }
        let p = session.location
        if let day = hitCell(at: p) { return .calendar(day) }
        if listFrame.contains(p) {
            return .list(navigation.selectedDay, index: insertionIndex(at: p))
        }
        return .none
    }

    /// Y of the insertion line, or nil when there is nothing to show.
    var insertionY: CGFloat? {
        guard let session, !session.isCompleted, case .list(_, let index) = target else { return nil }
        let frames = orderedRowFrames(excluding: session.taskID)
        if frames.isEmpty { return activeListFrame.minY }
        return index < frames.count ? frames[index].minY : frames[frames.count - 1].maxY
    }

    private func hitCell(at p: CGPoint) -> CalendarDay? {
        // No targets while the calendar is folded away.
        guard !UserDefaults.standard.bool(forKey: "calendarCollapsed") else { return nil }
        // Only the displayed month's cells count; an outgoing month's cells
        // can still report frames while they slide away.
        let visible = navigation.displayedMonth.gridDays()
        return visible.first { cellFrames[$0]?.contains(p) == true }
    }

    private func orderedRowFrames(excluding id: UUID) -> [CGRect] {
        activeRows.filter { $0 != id }.compactMap { rowFrames[$0] }
    }

    /// Index among the destination day's active rows (excluding the dragged
    /// task), matching `TaskStore.move(_:to:at:)`.
    private func insertionIndex(at p: CGPoint) -> Int {
        let frames = orderedRowFrames(excluding: session?.taskID ?? UUID())
        for (i, frame) in frames.enumerated() where p.y < frame.midY { return i }
        return frames.count
    }

    // MARK: Hover and dwell

    private func updateHover(at p: CGPoint) {
        // Calendar cells and month arrows share one dwell timer: a target
        // fires only if the pointer stays on it for the whole delay, so
        // crossing cells on the way to the list changes nothing.
        let key: AnyHashable?
        let delay: TimeInterval
        let action: () -> Void
        if let day = hitCell(at: p) {
            key = day
            delay = Self.cellDwell
            action = { [navigation] in
                withAnimation(.snappy(duration: 0.3)) { navigation.select(day) }
            }
        } else if previousMonthFrame.contains(p) {
            key = "previousMonth"
            delay = Self.arrowDwell
            action = { [navigation] in
                withAnimation(.snappy(duration: 0.3)) { Self.stepArrow(navigation, by: -1) }
            }
        } else if nextMonthFrame.contains(p) {
            key = "nextMonth"
            delay = Self.arrowDwell
            action = { [navigation] in
                withAnimation(.snappy(duration: 0.3)) { Self.stepArrow(navigation, by: 1) }
            }
        } else {
            key = nil
            delay = 0
            action = {}
        }
        if key != hoverKey {
            hoverKey = key
            dwellTimer?.invalidate()
            dwellTimer = nil
            if key != nil {
                dwellTimer = schedule(after: delay, repeats: false) { action() }
            }
        }
    }

    /// Mirrors the header arrows: months while the grid is shown, days when
    /// the calendar is collapsed.
    private static func stepArrow(_ navigation: DayNavigation, by amount: Int) {
        if UserDefaults.standard.bool(forKey: "calendarCollapsed") {
            navigation.select(navigation.selectedDay.adding(days: amount))
        } else {
            navigation.showMonth(navigation.displayedMonth.adding(months: amount))
        }
    }

    private func schedule(after interval: TimeInterval, repeats: Bool, _ block: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { _ in
            MainActor.assumeIsolated { block() }
        }
        // Common modes so the timer fires while the mouse button is held.
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func reset() {
        dwellTimer?.invalidate()
        dwellTimer = nil
        #if os(macOS)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        keyMonitor = nil
        mouseMonitor = nil
        #else
        pendingTouch = nil
        pendingOrigin = nil
        #endif
        session = nil
        hoverKey = nil
    }
}

/// Ghost row and insertion line, drawn over the whole
/// window in its coordinate space. Never intercepts the pointer.
struct DragOverlay: View {
    let drag: DragController

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let session = drag.session {
                if let y = drag.insertionY {
                    Rectangle()
                        .fill(Color.cookieAccent)
                        .frame(width: drag.listFrame.width - 32, height: 2)
                        .offset(x: drag.listFrame.minX + 16, y: y - 1)
                        .transition(.opacity)
                }
                if session.showsGhost { ghost(session) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func ghost(_ session: DragController.Session) -> some View {
        DragCard(text: session.text, isCompleted: session.isCompleted, width: session.width)
            .offset(
                x: session.location.x - session.grabOffset.width,
                y: session.location.y - session.grabOffset.height
            )
    }
}

/// A task as it looks while being dragged: the row's checkbox ring and
/// text on a lightly tinted card, so it reads as one rectangle picked up
/// off the list. The Mac draws it as the drag ghost; the iPhone hands it
/// to the system as the drag preview.
struct DragCard: View {
    let text: String
    let isCompleted: Bool
    let width: CGFloat
    /// Off on the iPhone, where the system draws its own shadow under the
    /// preview.
    var shadow = true

    private static let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
    #if os(macOS)
    private static let base = Color(nsColor: .windowBackgroundColor)
    #else
    private static let base = Color(uiColor: .systemBackground)
    #endif

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.5)
                .frame(width: CheckCircle.ringSize, height: CheckCircle.ringSize)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + CheckCircle.baselineOffset }
            Text(text)
                .font(TaskRow.rowFont)
                .strikethrough(isCompleted)
                .foregroundStyle(isCompleted ? .secondary : .primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, TaskRow.rowPadding)
        .frame(width: width)
        .background {
            // Opaque base so the list doesn't show through, then the same
            // tint as a hovered row, a shade stronger. A system color, not
            // the background style: the iPhone renders the preview outside
            // the view tree, where that style resolves to clear.
            Self.shape.fill(Self.base)
                .overlay(Self.shape.fill(Color.primary.opacity(0.07)))
                .overlay(Self.shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(shadow ? 0.22 : 0), radius: 10, y: 4)
        }
        .contentShape(.dragPreview, Self.shape)
    }
}

#if os(iOS)
/// Feeds a touch drag's position to the drag controller. Attached to the
/// whole planner, so the finger's location is already in the shared
/// coordinate space, and every release lands here (the planner fills the
/// screen), which is what ends the session.
struct TaskDropDelegate: DropDelegate {
    let drag: DragController

    func validateDrop(info: DropInfo) -> Bool {
        drag.isDragging || drag.hasPendingTouch
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        drag.updateTouch(location: info.location)
        // Always accept, even over places that aren't targets, so the
        // release always arrives in `performDrop` and ends the session.
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        drag.updateTouch(location: info.location)
        let moved = drag.target != .none
        drag.end()
        return moved
    }

    func dropExited(info: DropInfo) {
        drag.cancel()
    }
}
#endif

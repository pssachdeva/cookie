import SwiftUI
import AppKit
import CookieCore

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
final class DragController {
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
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var mouseMonitor: Any?

    private let navigation: DayNavigation
    private let store: TaskStore

    init(navigation: DayNavigation, store: TaskStore) {
        self.navigation = navigation
        self.store = store
    }

    var isDragging: Bool { session != nil }

    // MARK: Session

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
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        keyMonitor = nil
        mouseMonitor = nil
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
                ghost(session)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func ghost(_ session: DragController.Session) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.5)
                .frame(width: 18, height: 18)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            Text(session.text)
                .font(.body)
                .strikethrough(session.isCompleted)
                .foregroundStyle(session.isCompleted ? .secondary : .primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .frame(width: session.width)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        )
        .opacity(0.95)
        .offset(
            x: session.location.x - session.grabOffset.width,
            y: session.location.y - session.grabOffset.height
        )
    }
}

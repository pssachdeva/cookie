import Foundation
import Observation

/// Task store. The UI only talks to these operations and queries; saving
/// hangs off `onChange` (see `TaskFile`), so sync can replace it later.
@MainActor
@Observable
public final class TaskStore {
    public private(set) var tasks: [TaskItem]
    public var insertion: Insertion
    /// Called after every change to `tasks`.
    @ObservationIgnored public var onChange: (() -> Void)?

    public init(tasks: [TaskItem] = [], insertion: Insertion = .bottom) {
        self.tasks = tasks
        self.insertion = insertion
    }

    // MARK: Queries

    public func task(_ id: UUID) -> TaskItem? {
        tasks.first { $0.id == id }
    }

    /// Unfinished tasks on a day, in list order.
    public func activeTasks(on day: CalendarDay) -> [TaskItem] {
        tasks.filter { $0.day == day && $0.isActive }.sorted(by: Self.byOrder)
    }

    /// Completed tasks on a day, in completion order.
    public func completedTasks(on day: CalendarDay) -> [TaskItem] {
        tasks
            .filter { $0.day == day && $0.isCompleted && !$0.isDeleted }
            .sorted { ($0.completedAt!, $0.id.uuidString) < ($1.completedAt!, $1.id.uuidString) }
    }

    /// Unfinished tasks assigned to days before `day`, oldest day first.
    public func earlierUnfinished(before day: CalendarDay) -> [TaskItem] {
        tasks
            .filter { $0.day < day && $0.isActive }
            .sorted { ($0.day, $0.order, $0.id.uuidString) < ($1.day, $1.order, $1.id.uuidString) }
    }

    /// Days in a month that have at least one unfinished task.
    public func daysWithUnfinished(in month: CalendarMonth) -> Set<CalendarDay> {
        Set(tasks.filter { month.contains($0.day) && $0.isActive }.map(\.day))
    }

    // MARK: Operations

    /// Adds a task to `day` per the insertion setting. Returns nil when the
    /// text normalizes to nothing.
    @discardableResult
    public func add(_ raw: String, to day: CalendarDay) -> TaskItem? {
        guard let text = TaskText.normalized(raw) else { return nil }
        let active = activeTasks(on: day)
        let order = switch insertion {
        case .top: OrderKey.between(nil, active.first?.order)
        case .bottom: OrderKey.between(active.last?.order, nil)
        }
        let item = TaskItem(text: text, day: day, order: order)
        tasks.append(item)
        onChange?()
        return item
    }

    public func setCompleted(_ id: UUID, _ completed: Bool, at date: Date = .now) {
        update(id) { $0.completedAt = completed ? date : nil }
    }

    public func updateText(_ id: UUID, _ raw: String) {
        guard let text = TaskText.normalized(raw) else { return }
        update(id) { $0.text = text }
    }

    public func delete(_ id: UUID, at date: Date = .now) {
        update(id) { $0.deletedAt = date }
    }

    public func restore(_ id: UUID) {
        update(id) { $0.deletedAt = nil }
    }

    /// Moves a task to `day`, placing it before `index` in that day's active
    /// list (so `index == count` appends). Completed tasks keep their state
    /// and simply change day.
    public func move(_ id: UUID, to day: CalendarDay, at index: Int) {
        guard let item = task(id) else { return }
        let neighbors = activeTasks(on: day).filter { $0.id != id }
        let clamped = max(0, min(index, neighbors.count))
        let lower = clamped > 0 ? neighbors[clamped - 1].order : nil
        let upper = clamped < neighbors.count ? neighbors[clamped].order : nil
        update(id) {
            $0.day = day
            $0.order = item.isActive ? OrderKey.between(lower, upper) : $0.order
        }
    }

    /// Moves a task to `day` at the top or bottom per the insertion setting.
    public func move(_ id: UUID, to day: CalendarDay) {
        let count = activeTasks(on: day).filter { $0.id != id }.count
        move(id, to: day, at: insertion == .top ? 0 : count)
    }

    // MARK: Helpers

    private func update(_ id: UUID, _ change: (inout TaskItem) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        change(&tasks[index])
        tasks[index].modifiedAt = .now
        onChange?()
    }

    nonisolated private static func byOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        (a.order, a.id.uuidString) < (b.order, b.id.uuidString)
    }
}

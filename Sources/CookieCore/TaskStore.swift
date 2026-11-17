import Foundation
import Observation

/// Task store. The UI only talks to these operations and queries; saving
/// (`TaskFile`) and syncing (`CloudSync`) hang off `onChange`.
@MainActor
@Observable
public final class TaskStore {
    public private(set) var tasks: [TaskItem]
    public var insertion: Insertion
    /// Called after every change to `tasks`.
    @ObservationIgnored public var onChange: ((Change) -> Void)?

    /// Which tasks changed, and whether the change was made here (and so
    /// needs uploading) or arrived from another device.
    public struct Change: Sendable {
        public enum Origin: Sendable { case local, remote }
        public let ids: Set<UUID>
        public let origin: Origin
    }

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

    /// Days from `first` through `last` that have at least one unfinished
    /// task. A range rather than a month, since the month grid also shows
    /// the last days of the month before and the first of the month after.
    public func daysWithUnfinished(from first: CalendarDay, through last: CalendarDay) -> Set<CalendarDay> {
        Set(tasks.filter { $0.day >= first && $0.day <= last && $0.isActive }.map(\.day))
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
        onChange?(Change(ids: [item.id], origin: .local))
        return item
    }

    public func setCompleted(_ id: UUID, _ completed: Bool, at date: Date = .now) {
        update(id, .completion) { $0.completedAt = completed ? date : nil }
    }

    public func updateText(_ id: UUID, _ raw: String) {
        guard let text = TaskText.normalized(raw) else { return }
        update(id, .text) { $0.text = text }
    }

    public func delete(_ id: UUID, at date: Date = .now) {
        update(id, .deletion) { $0.deletedAt = date }
    }

    public func restore(_ id: UUID) {
        update(id, .deletion) { $0.deletedAt = nil }
    }

    /// Moves a task to `day`, placing it before `index` in that day's active
    /// list (so `index == count` appends). Completed tasks keep their state
    /// and simply change day. A move to where the task already is changes
    /// nothing, so a row picked up and put back isn't rewritten or synced.
    public func move(_ id: UUID, to day: CalendarDay, at index: Int) {
        guard let item = task(id) else { return }
        guard item.isActive else {
            if item.day != day { update(id, .placement) { $0.day = day } }
            return
        }
        let neighbors = activeTasks(on: day).filter { $0.id != id }
        let clamped = max(0, min(index, neighbors.count))
        let lower = clamped > 0 ? neighbors[clamped - 1] : nil
        let upper = clamped < neighbors.count ? neighbors[clamped] : nil
        if item.day == day,
           lower.map({ $0.order < item.order }) ?? true,
           upper.map({ item.order < $0.order }) ?? true {
            return
        }
        let order = OrderKey.between(lower?.order, upper?.order)
        if let lower, let upper, !(lower.order < order && order < upper.order) {
            // No key is left between the two neighbors: halving the same
            // gap runs out of precision after some fifty moves, and two
            // devices can hand out the same key.
            renumber(day, placing: id, before: upper.id)
            return
        }
        update(id, .placement) {
            $0.day = day
            $0.order = order
        }
    }

    /// Gives every task on `day` a whole-number key in its current order,
    /// with `id` placed just before `next`. Completed tasks are renumbered
    /// along with the active ones, so unchecking one still returns it to
    /// its place among them.
    private func renumber(_ day: CalendarDay, placing id: UUID, before next: UUID) {
        var ordered = tasks
            .filter { $0.day == day && !$0.isDeleted && $0.id != id }
            .sorted(by: Self.byOrder)
            .map(\.id)
        ordered.insert(id, at: ordered.firstIndex(of: next) ?? ordered.count)
        let positions = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1, Double($0)) })
        let now = Date.now
        var changed: Set<UUID> = []
        for index in tasks.indices {
            let taskID = tasks[index].id
            guard let order = positions[taskID],
                  taskID == id || tasks[index].order != order else { continue }
            tasks[index].day = day
            tasks[index].order = order
            tasks[index].touch(.placement, at: now)
            changed.insert(taskID)
        }
        onChange?(Change(ids: changed, origin: .local))
    }

    /// Moves a task to `day` at the top or bottom per the insertion setting.
    public func move(_ id: UUID, to day: CalendarDay) {
        let count = activeTasks(on: day).filter { $0.id != id }.count
        move(id, to: day, at: insertion == .top ? 0 : count)
    }

    // MARK: Remote changes and cleanup

    /// Merges versions of tasks received from another device, field group
    /// by field group. Unknown tasks are added as they are.
    public func applyRemote(_ incoming: [TaskItem]) {
        guard !incoming.isEmpty else { return }
        var positions = Dictionary(uniqueKeysWithValues: tasks.enumerated().map { ($1.id, $0) })
        for item in incoming {
            if let index = positions[item.id] {
                tasks[index] = tasks[index].merged(with: item)
            } else {
                positions[item.id] = tasks.count
                tasks.append(item)
            }
        }
        onChange?(Change(ids: Set(incoming.map(\.id)), origin: .remote))
    }

    /// Erases tasks another device has purged.
    public func removeRemote(_ ids: Set<UUID>) {
        guard !ids.isEmpty, tasks.contains(where: { ids.contains($0.id) }) else { return }
        tasks.removeAll { ids.contains($0.id) }
        onChange?(Change(ids: ids, origin: .remote))
    }

    /// Erases tasks deleted longer ago than `retention`, which is long
    /// enough for undo and for the deletion to reach other devices. Returns
    /// the erased IDs; this is a local change, so sync erases them too.
    @discardableResult
    public func purgeDeleted(olderThan retention: TimeInterval, now: Date = .now) -> Set<UUID> {
        let cutoff = now.addingTimeInterval(-retention)
        let old = Set(tasks.filter { ($0.deletedAt ?? .distantFuture) < cutoff }.map(\.id))
        guard !old.isEmpty else { return [] }
        tasks.removeAll { old.contains($0.id) }
        onChange?(Change(ids: old, origin: .local))
        return old
    }

    // MARK: Helpers

    private func update(_ id: UUID, _ field: FieldTimes.Field, _ change: (inout TaskItem) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        change(&tasks[index])
        tasks[index].touch(field)
        onChange?(Change(ids: [id], origin: .local))
    }

    nonisolated private static func byOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        (a.order, a.id.uuidString) < (b.order, b.id.uuidString)
    }
}

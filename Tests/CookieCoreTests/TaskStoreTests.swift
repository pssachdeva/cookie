import Testing
import Foundation
@testable import CookieCore

private let sep17 = CalendarDay(year: 2026, month: 9, day: 17)

@MainActor
struct TaskStoreTests {
    @Test func enterAddsInOrderAtBottom() {
        let store = TaskStore()
        store.add("one", to: sep17)
        store.add("two", to: sep17)
        store.add("three", to: sep17)
        #expect(store.activeTasks(on: sep17).map(\.text) == ["one", "two", "three"])
    }

    @Test func topInsertionDoesNotReverseExistingList() {
        let store = TaskStore()
        store.add("one", to: sep17)
        store.add("two", to: sep17)
        store.insertion = .top
        store.add("three", to: sep17)
        #expect(store.activeTasks(on: sep17).map(\.text) == ["three", "one", "two"])
    }

    @Test func whitespaceAndPasteNormalization() {
        let store = TaskStore()
        #expect(store.add("   \n\t ", to: sep17) == nil)
        let item = store.add("  first line\nsecond line \n", to: sep17)
        #expect(item?.text == "first line second line")
        let long = store.add(String(repeating: "x", count: 1200), to: sep17)
        #expect(long?.text.count == TaskText.maxLength)
    }

    @Test func uncheckingRestoresOldPosition() {
        let store = TaskStore()
        let ids = ["a", "b", "c", "d"].map { store.add($0, to: sep17)!.id }
        store.setCompleted(ids[1], true)
        #expect(store.activeTasks(on: sep17).map(\.text) == ["a", "c", "d"])
        store.setCompleted(ids[1], false)
        #expect(store.activeTasks(on: sep17).map(\.text) == ["a", "b", "c", "d"])
    }

    @Test func completingYesterdayTaskStaysOnYesterday() {
        let store = TaskStore()
        let sep16 = sep17.adding(days: -1)
        let id = store.add("old", to: sep16)!.id
        store.setCompleted(id, true)
        #expect(store.completedTasks(on: sep16).map(\.id) == [id])
        #expect(store.completedTasks(on: sep17).isEmpty)
        #expect(store.earlierUnfinished(before: sep17).isEmpty)
    }

    @Test func completedSectionOrderedByCompletionTime() {
        let store = TaskStore()
        let ids = ["a", "b", "c"].map { store.add($0, to: sep17)!.id }
        let t0 = Date(timeIntervalSince1970: 1_000)
        store.setCompleted(ids[2], true, at: t0)
        store.setCompleted(ids[0], true, at: t0 + 10)
        store.setCompleted(ids[1], true, at: t0 + 20)
        #expect(store.completedTasks(on: sep17).map(\.text) == ["c", "a", "b"])
    }

    @Test func earlierUnfinishedIsOldestFirstAndExcludesToday() {
        let store = TaskStore()
        store.add("today", to: sep17)
        store.add("yesterday", to: sep17.adding(days: -1))
        store.add("last month", to: sep17.adding(days: -30))
        #expect(store.earlierUnfinished(before: sep17).map(\.text) == ["last month", "yesterday"])
    }

    @Test func moveBetweenDaysAtPosition() {
        let store = TaskStore()
        let sep18 = sep17.adding(days: 1)
        let moving = store.add("moving", to: sep17)!.id
        store.add("x", to: sep18)
        store.add("y", to: sep18)
        store.move(moving, to: sep18, at: 1)
        #expect(store.activeTasks(on: sep17).isEmpty)
        #expect(store.activeTasks(on: sep18).map(\.text) == ["x", "moving", "y"])
    }

    @Test func droppingATaskWhereItIsChangesNothing() {
        let store = TaskStore()
        let ids = ["a", "b", "c"].map { store.add($0, to: sep17)!.id }
        let before = store.tasks
        var changes = 0
        store.onChange = { _ in changes += 1 }

        // Each position counts the other rows only, as a drop does.
        for (index, id) in ids.enumerated() { store.move(id, to: sep17, at: index) }
        // The same through the menu's "move to this day".
        store.move(ids[2], to: sep17)
        store.setCompleted(ids[0], true)
        changes = 0
        store.move(ids[0], to: sep17)

        #expect(changes == 0)
        #expect(store.tasks.map(\.order) == before.map(\.order))
        #expect(store.task(ids[1]) == before[1])
    }

    @Test func manyMovesIntoTheSameGapKeepTheirOrder() {
        let store = TaskStore()
        store.add("top", to: sep17)
        store.add("first", to: sep17)
        store.add("last", to: sep17)
        var mostChangedAtOnce = 0
        store.onChange = { mostChangedAtOnce = max(mostChangedAtOnce, $0.ids.count) }
        // Each new task goes just under "first", above the one before it.
        // Halving the gap under a key of 1 runs out of room at the 53rd.
        var expected: [String] = []
        for number in 1...60 {
            let id = store.add("task \(number)", to: sep17)!.id
            store.move(id, to: sep17, at: 2)
            expected.insert("task \(number)", at: 0)
        }
        let active = store.activeTasks(on: sep17)
        #expect(active.map(\.text) == ["top", "first"] + expected + ["last"])
        #expect(Set(active.map(\.order)).count == active.count)
        // The day was renumbered along the way, not only the moved task.
        #expect(mostChangedAtOnce > 1)
    }

    @Test func aCompletedTaskKeepsItsPlaceWhenTheDayIsRenumbered() {
        let store = TaskStore()
        store.add("top", to: sep17)
        let first = store.add("first", to: sep17)!.id
        let middle = store.add("middle", to: sep17)!.id
        let last = store.add("last", to: sep17)!.id
        store.setCompleted(middle, true)
        var mostChangedAtOnce = 0
        store.onChange = { mostChangedAtOnce = max(mostChangedAtOnce, $0.ids.count) }
        for number in 1...60 {
            let id = store.add("task \(number)", to: sep17)!.id
            store.move(id, to: sep17, at: 2)
        }
        #expect(mostChangedAtOnce > 1)
        store.setCompleted(middle, false)
        let order = store.activeTasks(on: sep17).map(\.id)
        let place = try! #require(order.firstIndex(of: middle))
        #expect(order.firstIndex(of: first)! < place)
        #expect(place < order.firstIndex(of: last)!)
    }

    @Test func deleteIsRestorable() {
        let store = TaskStore()
        let id = store.add("gone", to: sep17)!.id
        store.delete(id)
        #expect(store.activeTasks(on: sep17).isEmpty)
        #expect(store.daysWithUnfinished(in: sep17.calendarMonth).isEmpty)
        store.restore(id)
        #expect(store.activeTasks(on: sep17).map(\.id) == [id])
    }
}

struct CalendarMathTests {
    @Test func gridStartsOnFirstWeekdayAndHas42Days() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        let grid = CalendarMonth(year: 2026, month: 9).gridDays(calendar: calendar)
        #expect(grid.count == 42)
        // September 1, 2026 is a Tuesday, so the grid starts Monday, August 31.
        #expect(grid.first == CalendarDay(year: 2026, month: 8, day: 31))
        #expect(grid.last == CalendarDay(year: 2026, month: 10, day: 11))
    }

    @Test func dayArithmeticCrossesMonths() {
        #expect(sep17.adding(days: 14) == CalendarDay(year: 2026, month: 10, day: 1))
        #expect(sep17.calendarMonth.adding(months: -1) == CalendarMonth(year: 2026, month: 8))
        #expect(CalendarMonth(year: 2026, month: 12).adding(months: 1) == CalendarMonth(year: 2027, month: 1))
    }
}

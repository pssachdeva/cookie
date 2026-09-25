import Testing
import Foundation
@testable import CookieCore

private let sep17 = CalendarDay(year: 2026, month: 9, day: 17)

@MainActor
struct TaskFileTests {
    /// A fresh directory per test, removed afterwards.
    private func withTempFile(_ body: (URL) throws -> Void) rethrows {
        let dir = FileManager.default.temporaryDirectory.appending(path: "cookie-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir.appending(path: "tasks.json"))
    }

    @Test func roundTripKeepsEverything() throws {
        try withTempFile { url in
            let store = TaskStore()
            let a = store.add("first", to: sep17)!
            store.add("second", to: sep17.adding(days: 1))
            store.setCompleted(a.id, true)

            let file = TaskFile(url: url)
            file.saveNow(store.tasks)
            let loaded = file.load()
            #expect(loaded.map(\.id) == store.tasks.map(\.id))
            #expect(loaded.map(\.text) == store.tasks.map(\.text))
            #expect(loaded.map(\.day) == store.tasks.map(\.day))
            #expect(loaded.map(\.order) == store.tasks.map(\.order))
            #expect(loaded.map(\.isCompleted) == store.tasks.map(\.isCompleted))
            // Dates are stored to the millisecond.
            for (a, b) in zip(loaded, store.tasks) {
                #expect(abs(a.modifiedAt.timeIntervalSince(b.modifiedAt)) < 0.001)
                #expect(abs(a.createdAt.timeIntervalSince(b.createdAt)) < 0.001)
            }
        }
    }

    @Test func missingFileLoadsEmpty() {
        withTempFile { url in
            #expect(TaskFile(url: url).load().isEmpty)
        }
    }

    @Test func unreadableFileIsMovedAsideNotOverwritten() throws {
        try withTempFile { url in
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("not json".utf8).write(to: url)

            #expect(TaskFile(url: url).load().isEmpty)
            let siblings = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path())
            #expect(siblings.contains { $0.hasPrefix("tasks-unreadable-") })
            #expect(!FileManager.default.fileExists(atPath: url.path()))
        }
    }

    @Test func oldDeletedTasksArePurgedOnLoad() throws {
        try withTempFile { url in
            let now = Date.now
            let store = TaskStore()
            let recent = store.add("deleted yesterday", to: sep17)!
            let old = store.add("deleted long ago", to: sep17)!
            store.delete(recent.id, at: now.addingTimeInterval(-86_400))
            store.delete(old.id, at: now.addingTimeInterval(-40 * 86_400))

            let file = TaskFile(url: url)
            file.saveNow(store.tasks)
            #expect(file.load(now: now).map(\.text) == ["deleted yesterday"])
        }
    }

    @Test func completionOrderWithinOneSecondSurvivesReload() throws {
        try withTempFile { url in
            let store = TaskStore()
            let ids = ["a", "b", "c"].map { store.add($0, to: sep17)!.id }
            let base = Date(timeIntervalSince1970: 1_800_000_000)
            // Completed in reverse order, 10 ms apart.
            for (i, id) in ids.reversed().enumerated() {
                store.setCompleted(id, true, at: base.addingTimeInterval(Double(i) * 0.01))
            }

            let file = TaskFile(url: url)
            file.saveNow(store.tasks)
            let reloaded = TaskStore(tasks: file.load())
            #expect(reloaded.completedTasks(on: sep17).map(\.text) == ["c", "b", "a"])
        }
    }

    @Test func storeReportsEveryChange() {
        let store = TaskStore()
        var changes = 0
        store.onChange = { changes += 1 }
        let item = store.add("one", to: sep17)!
        store.updateText(item.id, "uno")
        store.setCompleted(item.id, true)
        store.move(item.id, to: sep17.adding(days: 1))
        store.delete(item.id)
        #expect(changes == 5)
    }
}

import Testing
import Foundation
@testable import CookieCore

private let sep17 = CalendarDay(year: 2026, month: 9, day: 17)
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let taskID = UUID()

/// One task as last changed at `t0`, for building diverging versions.
private func base() -> TaskItem {
    TaskItem(id: taskID, text: "original", day: sep17, order: 1, createdAt: t0, modifiedAt: t0)
}

struct MergeTests {
    @Test func differentFieldsChangedOnEachSideBothSurvive() {
        var mac = base()
        mac.text = "edited on Mac"
        mac.touch(.text, at: t0 + 10)
        var phone = base()
        phone.completedAt = t0 + 20
        phone.touch(.completion, at: t0 + 20)

        for merged in [mac.merged(with: phone), phone.merged(with: mac)] {
            #expect(merged.text == "edited on Mac")
            #expect(merged.isCompleted)
            #expect(merged.modifiedAt == t0 + 20)
        }
    }

    @Test func sameFieldLaterChangeWins() {
        var a = base()
        a.text = "earlier"
        a.touch(.text, at: t0 + 10)
        var b = base()
        b.text = "later"
        b.touch(.text, at: t0 + 30)
        #expect(a.merged(with: b).text == "later")
        #expect(b.merged(with: a).text == "later")
    }

    @Test func dayAndOrderMoveTogether() {
        var a = base()
        a.day = sep17.adding(days: 1)
        a.order = 7
        a.touch(.placement, at: t0 + 10)
        var b = base()
        b.order = 3
        b.touch(.placement, at: t0 + 5)
        let merged = b.merged(with: a)
        #expect(merged.day == sep17.adding(days: 1))
        #expect(merged.order == 7)
    }

    @Test func deletionSurvivesAnEditElsewhere() {
        var deleted = base()
        deleted.deletedAt = t0 + 10
        deleted.touch(.deletion, at: t0 + 10)
        var edited = base()
        edited.text = "edited after"
        edited.touch(.text, at: t0 + 20)
        let merged = edited.merged(with: deleted)
        #expect(merged.isDeleted)
        #expect(merged.text == "edited after")
    }

    @Test func tiesResolveTheSameWayOnEveryDevice() {
        var a = base()
        a.text = "alpha"
        a.touch(.text, at: t0 + 10)
        var b = base()
        b.text = "beta"
        b.touch(.text, at: t0 + 10)
        #expect(a.merged(with: b) == b.merged(with: a))
    }
}

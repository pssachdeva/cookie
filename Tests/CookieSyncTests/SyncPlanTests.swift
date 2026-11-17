import Testing
import Foundation
import CookieCore
@testable import CookieSync

private let sep24 = CalendarDay(year: 2026, month: 9, day: 24)
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

/// A task last changed at `t0`, or with the given times for each part.
private func task(
    _ text: String = "original",
    id: UUID = UUID(),
    completedAt: Date? = nil,
    times: FieldTimes = FieldTimes(all: t0)
) -> TaskItem {
    TaskItem(id: id, text: text, day: sep24, order: 1, completedAt: completedAt, createdAt: t0, fieldTimes: times)
}

/// What sync remembers about tasks the server holds as given.
private func known(_ tasks: TaskItem...) -> [UUID: SyncState.RecordInfo] {
    Dictionary(uniqueKeysWithValues: tasks.map {
        ($0.id, SyncState.RecordInfo(systemFields: Data(), server: $0))
    })
}

private func times(text: Date = t0, completion: Date = t0) -> FieldTimes {
    FieldTimes(text: text, placement: t0, completion: completion, deletion: t0)
}

struct SyncPlanTests {
    // MARK: Deletes

    @Test func aMissingTaskFileDeletesNothing() {
        let a = task(), b = task()
        let plan = SyncPlan.startup(tasks: [], records: known(a, b), pendingDeletes: [])
        #expect(plan.deletes.isEmpty)
        #expect(plan.saves.isEmpty)
        #expect(plan.orphans == [a.id, b.id])
    }

    @Test func anOlderTaskFileDeletesNothing() {
        let kept = task(), addedSince = task()
        let plan = SyncPlan.startup(tasks: [kept], records: known(kept, addedSince), pendingDeletes: [])
        #expect(plan.deletes.isEmpty)
        #expect(plan.orphans == [addedSince.id])
    }

    @Test func aRecordedPurgeIsDeleted() {
        let kept = task(), purged = task()
        let plan = SyncPlan.startup(tasks: [kept], records: known(kept, purged), pendingDeletes: [purged.id])
        #expect(plan.deletes == [purged.id])
        #expect(plan.orphans.isEmpty)
        #expect(plan.saves.isEmpty)
    }

    @Test func aRecordedPurgeSurvivesARelaunch() throws {
        let kept = task(), purged = task()
        let url = FileManager.default.temporaryDirectory.appending(path: "cookie-sync-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }
        let file = SyncStateFile(url: url)
        file.save(SyncState(records: known(kept, purged), pendingDeletes: [purged.id]))

        let loaded = file.load()
        #expect(try #require(loaded.records[kept.id]?.server).hasSameContent(as: kept))
        let plan = SyncPlan.startup(tasks: [kept], records: loaded.records, pendingDeletes: loaded.pendingDeletes)
        #expect(plan.deletes == [purged.id])
        #expect(plan.orphans.isEmpty)
        #expect(plan.saves.isEmpty)
    }

    @Test func aTaskBackInTheStoreIsNotDeleted() {
        let restored = task()
        let plan = SyncPlan.startup(tasks: [restored], records: known(restored), pendingDeletes: [restored.id])
        #expect(plan.deletes.isEmpty)
    }

    // MARK: Uploads

    @Test func aTaskTheServerHasNeverSeenIsUploaded() {
        let new = task()
        let plan = SyncPlan.startup(tasks: [new], records: [:], pendingDeletes: [])
        #expect(plan.saves == [new.id])
    }

    @Test func anUpToDateTaskIsLeftAlone() {
        let same = task()
        let plan = SyncPlan.startup(tasks: [same], records: known(same), pendingDeletes: [])
        #expect(plan == SyncPlan.Startup())
    }

    /// The Mac edits the text; the iPhone then completes the task and
    /// uploads first. The merged task is no newer than the iPhone's, but
    /// it holds the Mac's text, which the server has never seen.
    @Test func anOlderEditStillGoesUpAfterANewerChangeElsewhere() {
        let id = UUID()
        let mac = task("edited on Mac", id: id, times: times(text: t0 + 10))
        let phone = task(id: id, completedAt: t0 + 20, times: times(completion: t0 + 20))

        let merged = mac.merged(with: phone)
        #expect(merged.modifiedAt == phone.modifiedAt)
        #expect(SyncPlan.needsUpload(local: merged, server: phone))
        // Once the server has taken the merged task, there is nothing to send.
        #expect(!SyncPlan.needsUpload(local: merged, server: merged))
        #expect(SyncPlan.startup(tasks: [merged], records: known(merged), pendingDeletes: []).saves.isEmpty)
    }

    @Test func theSideThatWinsATieUploads() {
        let id = UUID()
        let alpha = task("alpha", id: id, times: times(text: t0 + 10))
        let beta = task("beta", id: id, times: times(text: t0 + 10))
        #expect(SyncPlan.needsUpload(local: beta, server: alpha))
        #expect(!SyncPlan.needsUpload(local: alpha, server: beta))
    }

    // MARK: A task file older than the server's copies

    @Test func aTaskBehindTheServerIsCaughtUpNotUploaded() {
        let id = UUID()
        let restored = task(id: id)
        let server = task(id: id, completedAt: t0 + 20, times: times(completion: t0 + 20))
        let plan = SyncPlan.startup(tasks: [restored], records: known(server), pendingDeletes: [])
        #expect(plan.stale == [id])
        #expect(plan.saves.isEmpty)
    }

    @Test func aTaskBothBehindAndAheadIsCaughtUpThenUploaded() {
        let id = UUID()
        let local = task("edited here", id: id, times: times(text: t0 + 30))
        let server = task(id: id, completedAt: t0 + 20, times: times(completion: t0 + 20))
        let plan = SyncPlan.startup(tasks: [local], records: known(server), pendingDeletes: [])
        #expect(plan.stale == [id])
        #expect(plan.saves == [id])
    }

    // MARK: State saved by earlier versions

    /// Earlier versions kept only the server's modification time per task
    /// and had no list of purges.
    @Test func stateFromBeforeTheseFieldsStillLoads() throws {
        struct OldState: Codable {
            var records: [UUID: Info]
            struct Info: Codable {
                var systemFields: Data
                var serverModifiedAt: Date
            }
        }
        let synced = task()
        let url = FileManager.default.temporaryDirectory.appending(path: "cookie-sync-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }
        let old = OldState(records: [synced.id: .init(systemFields: Data([1, 2, 3]), serverModifiedAt: t0)])
        try PropertyListEncoder().encode(old).write(to: url)

        let loaded = SyncStateFile(url: url).load()
        #expect(loaded.records[synced.id]?.systemFields == Data([1, 2, 3]))
        #expect(loaded.records[synced.id]?.server == nil)
        #expect(loaded.pendingDeletes.isEmpty)
        // Known to the server, so not an orphan; uploaded once more, since
        // what the server holds is no longer on record.
        let plan = SyncPlan.startup(tasks: [synced], records: loaded.records, pendingDeletes: loaded.pendingDeletes)
        #expect(plan.orphans.isEmpty)
        #expect(plan.saves == [synced.id])
    }
}

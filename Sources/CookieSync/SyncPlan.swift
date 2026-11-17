import CookieCore
import Foundation

/// The decisions sync makes about what to send, kept apart from CloudKit so
/// they can be tested without an iCloud container.
enum SyncPlan {
    /// What to queue when sync starts.
    struct Startup: Equatable {
        /// Tasks holding something the server's copy lacks.
        var saves: Set<UUID> = []
        /// Tasks whose server copy, already on hand, has a change the store
        /// lacks: the task file is older than the sync state (restored from
        /// a backup, say). They are merged with that copy before anything
        /// is sent, so an old value never overwrites a newer one.
        var stale: Set<UUID> = []
        /// Tasks purged here whose records are still on the server.
        var deletes: Set<UUID> = []
        /// Tasks the server is known to hold that are missing from the store
        /// without having been purged. The task file lost them (it was
        /// removed, unreadable, or restored from an older copy), so they
        /// are fetched again, never deleted.
        var orphans: Set<UUID> = []
    }

    /// Whether `local` has anything the server's copy lacks: merging the
    /// two gives something other than the server's copy. True when the
    /// server has no copy. Compares the values, not only the times: a merge
    /// can keep an older local field beside a newer server one, or win a tie
    /// at the same time, and still differ from what the server holds. False
    /// when `local` is merely behind, which is no reason to send it.
    static func needsUpload(local: TaskItem, server: TaskItem?) -> Bool {
        guard let server else { return true }
        return !local.merged(with: server).hasSameContent(as: server)
    }

    /// Whether the server's copy changed some part of the task after
    /// `local` did.
    static func isBehind(local: TaskItem, server: TaskItem) -> Bool {
        FieldTimes.Field.allCases.contains {
            server.fieldTimes[$0].isLater(than: local.fieldTimes[$0])
        }
    }

    /// Compares the store against what the server is known to hold. A record
    /// is deleted only when its purge was recorded in `pendingDeletes`; a
    /// task that is merely absent from the store is an orphan.
    static func startup(
        tasks: [TaskItem],
        records: [UUID: SyncState.RecordInfo],
        pendingDeletes: Set<UUID>
    ) -> Startup {
        var plan = Startup()
        var live: Set<UUID> = []
        for task in tasks {
            live.insert(task.id)
            let server = records[task.id]?.server
            if needsUpload(local: task, server: server) {
                plan.saves.insert(task.id)
            }
            if let server, isBehind(local: task, server: server) {
                plan.stale.insert(task.id)
            }
        }
        // A task that is back in the store is no longer purged.
        plan.deletes = pendingDeletes.subtracting(live)
        plan.orphans = Set(records.keys).subtracting(live).subtracting(pendingDeletes)
        return plan
    }
}

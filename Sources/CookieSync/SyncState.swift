import CloudKit
import CookieCore
import Foundation

/// What sync remembers between launches: the engine's own state (its
/// change tokens and pending queue), for each task the server's last copy
/// of the record, and the purges still to be sent.
struct SyncState: Codable {
    var engine: CKSyncEngine.State.Serialization?
    var records: [UUID: RecordInfo] = [:]
    /// Tasks purged here whose records are still to be deleted from the
    /// server. Written down when the purge happens, so a record is only
    /// ever deleted because a task was purged, never because the task file
    /// happens not to contain it.
    var pendingDeletes: Set<UUID> = []

    struct RecordInfo: Codable {
        /// `CKRecord` system fields (change tag and so on), so a save is
        /// built on the server's copy instead of conflicting with it.
        var systemFields: Data
        /// The task as the server holds it. A local task that differs has
        /// changes still to upload. Nil in state saved by a version that
        /// kept only a time here; such a task is uploaded once more.
        var server: TaskItem?
    }
}

extension SyncState {
    /// State saved before `pendingDeletes` existed still loads.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        engine = try c.decodeIfPresent(CKSyncEngine.State.Serialization.self, forKey: .engine)
        records = try c.decodeIfPresent([UUID: RecordInfo].self, forKey: .records) ?? [:]
        pendingDeletes = try c.decodeIfPresent(Set<UUID>.self, forKey: .pendingDeletes) ?? []
    }
}

/// Reads and writes `SyncState` as a file beside the task file.
struct SyncStateFile {
    let url: URL

    func load() -> SyncState {
        guard let data = try? Data(contentsOf: url),
              let state = try? PropertyListDecoder().decode(SyncState.self, from: data)
        else {
            // Missing or unreadable: start over. The first sync re-uploads
            // and merges, so nothing is lost.
            return SyncState()
        }
        return state
    }

    func save(_ state: SyncState) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            try encoder.encode(state).write(to: url, options: .atomic)
        } catch {
            print("Cookie: could not save sync state: \(error)")
        }
    }
}

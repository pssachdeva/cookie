import CloudKit
import Foundation

/// What sync remembers between launches: the engine's own state (its
/// change tokens and pending queue), and for each task the server's last
/// copy of the record's bookkeeping plus the version the server holds.
struct SyncState: Codable {
    var engine: CKSyncEngine.State.Serialization?
    var records: [UUID: RecordInfo] = [:]

    struct RecordInfo: Codable {
        /// `CKRecord` system fields (change tag and so on), so a save is
        /// built on the server's copy instead of conflicting with it.
        var systemFields: Data
        /// The task's `modifiedAt` as the server has it. A local task newer
        /// than this has changes still to upload.
        var serverModifiedAt: Date
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

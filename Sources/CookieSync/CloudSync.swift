import CloudKit
import CookieCore
import OSLog
import Security

/// Sync diagnostics. Follow with:
/// `log stream --predicate 'subsystem == "com.psachdeva.cookie"' --info`
private let log = Logger(subsystem: "com.psachdeva.cookie", category: "sync")

/// Keeps the task store in step with the user's private iCloud database
/// through `CKSyncEngine`. The local task file stays the source the app
/// reads from, so everything works offline; this layer uploads local
/// changes, merges in changes from other devices field by field, and
/// removes tasks another device has purged.
@MainActor
public final class CloudSync: CKSyncEngineDelegate {
    public static let containerIdentifier = "iCloud.com.psachdeva.cookie"

    private let store: TaskStore
    private let database: CKDatabase
    private let stateFile: SyncStateFile
    /// Writes the task file now. Called before sync state is saved, so the
    /// state never claims changes the task file doesn't hold yet.
    private let flushTasks: () -> Void
    private var state: SyncState
    private var engine: CKSyncEngine?
    private var pendingSend: Task<Void, Never>?

    public init(store: TaskStore, stateURL: URL, flushTasks: @escaping () -> Void) {
        self.store = store
        self.database = CKContainer(identifier: Self.containerIdentifier).privateCloudDatabase
        self.stateFile = SyncStateFile(url: stateURL)
        self.flushTasks = flushTasks
        self.state = stateFile.load()
    }

    /// True when this build is signed with the iCloud entitlement. Script
    /// builds aren't, and CloudKit would refuse (or crash) without it.
    public static var isEntitled: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let services = SecTaskCopyValueForEntitlement(
                task, "com.apple.developer.icloud-services" as CFString, nil
              ) as? [String]
        else { return false }
        return services.contains("CloudKit")
        #else
        // iOS can't read its own entitlements; the provisioning profile it
        // was installed with lists them instead. Simulator builds and builds
        // from teams without iCloud have no profile granting it.
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let profile = String(data: data, encoding: .isoLatin1)
        else { return false }
        return profile.contains("com.apple.developer.icloud-services")
            && profile.contains(containerIdentifier)
        #endif
    }

    public func start() {
        guard engine == nil else { return }
        let firstRun = state.engine == nil
        let engine = CKSyncEngine(CKSyncEngine.Configuration(
            database: database, stateSerialization: state.engine, delegate: self
        ))
        self.engine = engine
        if firstRun {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: TaskRecord.zoneID))])
        }
        queueUnsyncedChanges()
        log.notice("started; firstRun=\(firstRun) pendingRecords=\(engine.state.pendingRecordZoneChanges.count) pendingDatabase=\(engine.state.pendingDatabaseChanges.count)")
        // The engine's own scheduler can wait minutes; the spec wants
        // changes across within seconds, so send right away.
        scheduleSend(after: 0)
    }

    /// Queues local changes for upload. Called for every local store change.
    public func localChange(_ ids: Set<UUID>) {
        guard let engine else { return }
        engine.state.add(pendingRecordZoneChanges: ids.map { id in
            let recordID = TaskRecord.recordID(for: id)
            return store.task(id) != nil ? .saveRecord(recordID) : .deleteRecord(recordID)
        })
        // Short debounce so a burst of edits goes up as one batch.
        scheduleSend(after: 0.5)
    }

    /// Sends pending changes after `delay`, replacing any send already
    /// waiting. The engine retries on its own if the send fails.
    private func scheduleSend(after delay: TimeInterval) {
        pendingSend?.cancel()
        pendingSend = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
            }
            guard let engine = self?.engine else { return }
            do {
                try await engine.sendChanges()
            } catch {
                log.error("sendChanges failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Asks the server for changes now, rather than waiting for a push.
    public func fetchChanges() {
        guard let engine else { return }
        Task {
            do {
                try await engine.fetchChanges()
            } catch {
                log.error("fetchChanges failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        // Anything queued while the app was in the background goes now too.
        scheduleSend(after: 0)
    }

    /// Compares the store against what the server is known to have, and
    /// queues whatever differs. Covers the first sync, and any change made
    /// just before a quit or crash that didn't make it into the saved queue.
    private func queueUnsyncedChanges() {
        guard let engine else { return }
        var pending: [CKSyncEngine.PendingRecordZoneChange] = []
        for task in store.tasks {
            let server = state.records[task.id]?.serverModifiedAt
            if server.map({ task.modifiedAt.isLater(than: $0) }) ?? true {
                pending.append(.saveRecord(TaskRecord.recordID(for: task.id)))
            }
        }
        let live = Set(store.tasks.map(\.id))
        for id in state.records.keys where !live.contains(id) {
            pending.append(.deleteRecord(TaskRecord.recordID(for: id)))
        }
        engine.state.add(pendingRecordZoneChanges: pending)
    }

    // MARK: CKSyncEngineDelegate

    nonisolated public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await handle(event)
    }

    nonisolated public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            await self.recordToSave(recordID)
        }
    }

    // MARK: Events

    private func handle(_ event: CKSyncEngine.Event) {
        switch event {
        case .stateUpdate(let update):
            state.engine = update.stateSerialization
            saveState()

        case .accountChange(let change):
            log.notice("account change: \(String(describing: change.changeType), privacy: .public)")
            switch change.changeType {
            case .signIn:
                // Upload everything to the new account.
                state.records = [:]
                engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: TaskRecord.zoneID))])
                queueUnsyncedChanges()
            case .signOut, .switchAccounts:
                // Tasks stay on this Mac; only the link to the old account's
                // records is dropped. A new sign-in uploads them afresh.
                state.records = [:]
            @unknown default:
                break
            }
            saveState()

        case .fetchedDatabaseChanges(let changes):
            // The zone was deleted elsewhere (another device reset, or iCloud
            // data cleared in Settings). Keep this Mac's tasks and upload
            // them again rather than erasing anything on a remote signal.
            if changes.deletions.contains(where: { $0.zoneID == TaskRecord.zoneID }) {
                state.records = [:]
                engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: TaskRecord.zoneID))])
                queueUnsyncedChanges()
                saveState()
            }

        case .fetchedRecordZoneChanges(let changes):
            log.notice("fetched \(changes.modifications.count) modified, \(changes.deletions.count) deleted")
            var incoming: [TaskItem] = []
            for modification in changes.modifications {
                let record = modification.record
                guard let item = TaskRecord.item(from: record) else { continue }
                remember(record, as: item)
                incoming.append(item)
            }
            let deleted = Set(changes.deletions.compactMap { TaskRecord.taskID(of: $0.recordID) })
            for id in deleted { state.records[id] = nil }
            store.applyRemote(incoming)
            store.removeRemote(deleted)
            flushTasks()
            saveState()

        case .sentDatabaseChanges(let sent):
            log.notice("sent database changes: \(sent.savedZones.count) zones saved, \(sent.failedZoneSaves.count) failed")
            for failure in sent.failedZoneSaves {
                log.error("zone save failed: \(failure.error.localizedDescription, privacy: .public)")
            }

        case .sentRecordZoneChanges(let sent):
            log.notice("sent: \(sent.savedRecords.count) saved, \(sent.deletedRecordIDs.count) deleted, \(sent.failedRecordSaves.count) failed saves, \(sent.failedRecordDeletes.count) failed deletes")
            for record in sent.savedRecords {
                if let item = TaskRecord.item(from: record) { remember(record, as: item) }
            }
            for recordID in sent.deletedRecordIDs {
                if let id = TaskRecord.taskID(of: recordID) { state.records[id] = nil }
            }
            handleFailedSaves(sent.failedRecordSaves)
            flushTasks()
            saveState()

        default:
            break
        }
    }

    private func handleFailedSaves(_ failures: [CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave]) {
        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        var needsZone = false
        for failure in failures {
            let recordID = failure.record.recordID
            guard let id = TaskRecord.taskID(of: recordID) else { continue }
            switch failure.error.code {
            case .serverRecordChanged:
                // Another device saved first: merge its version in, then
                // send the result if it still differs from the server's.
                guard let server = failure.error.serverRecord,
                      let item = TaskRecord.item(from: server) else { continue }
                remember(server, as: item)
                store.applyRemote([item])
                if let merged = store.task(id), merged.modifiedAt.isLater(than: item.modifiedAt) {
                    retry.append(.saveRecord(recordID))
                }
            case .zoneNotFound:
                needsZone = true
                state.records[id] = nil
                retry.append(.saveRecord(recordID))
            case .unknownItem:
                // The server lost the record; send it as new.
                state.records[id] = nil
                retry.append(.saveRecord(recordID))
            default:
                // Network, throttling, and account errors are retried by the
                // engine on its own schedule.
                log.error("save failed (\(failure.error.code.rawValue)): \(failure.error.localizedDescription, privacy: .public)")
            }
        }
        if needsZone {
            engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: TaskRecord.zoneID))])
        }
        engine?.state.add(pendingRecordZoneChanges: retry)
    }

    /// The record to upload for a pending save, built on the server's last
    /// copy when there is one. Nil (and dropped from the queue) when the
    /// task no longer exists locally.
    private func recordToSave(_ recordID: CKRecord.ID) -> CKRecord? {
        guard let id = TaskRecord.taskID(of: recordID), let task = store.task(id) else {
            engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            return nil
        }
        let record = state.records[id].flatMap { CKRecord.fromSystemFields($0.systemFields) }
            ?? CKRecord(recordType: TaskRecord.recordType, recordID: recordID)
        TaskRecord.fill(record, from: task)
        return record
    }

    private func remember(_ record: CKRecord, as item: TaskItem) {
        state.records[item.id] = SyncState.RecordInfo(
            systemFields: record.encodedSystemFields,
            serverModifiedAt: item.modifiedAt
        )
    }

    private func saveState() {
        stateFile.save(state)
    }
}

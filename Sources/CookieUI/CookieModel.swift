import Foundation
import CookieCore
import CookieSync

/// The app's data, set up the same way on every platform: tasks loaded from
/// the task file and saved back after each change, deleted tasks past their
/// retention purged, and iCloud sync started when the build allows it.
@MainActor
public final class CookieModel {
    public let store: TaskStore
    public let sync: CloudSync?
    private let file: TaskFile?

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        // COOKIE_SAMPLE_DATA=1 runs on the prototype's sample tasks, in
        // memory only, so trying things out never touches saved tasks.
        if environment["COOKIE_SAMPLE_DATA"] == "1" {
            store = .sample()
            sync = nil
            file = nil
            return
        }
        let file = TaskFile(url: TaskFile.defaultURL())
        let store = TaskStore(tasks: file.load())

        // iCloud sync needs a build signed with the iCloud entitlement, and
        // stays off for scratch data so test tasks never reach iCloud.
        let syncEnabled = CloudSync.isEntitled
            && environment["COOKIE_DATA_DIR"] == nil
            && environment["COOKIE_DISABLE_SYNC"] != "1"
        let sync = syncEnabled ? CloudSync(
            store: store,
            stateURL: file.url.deletingLastPathComponent().appending(path: "sync-state.plist"),
            flushTasks: { [weak store] in if let store { file.saveNow(store.tasks) } }
        ) : nil

        store.onChange = { [weak store] change in
            guard let store else { return }
            file.scheduleSave { store.tasks }
            if change.origin == .local { sync?.localChange(change.ids) }
        }
        store.purgeDeleted(olderThan: TaskFile.deletedRetention)
        sync?.start()

        self.store = store
        self.sync = sync
        self.file = file
    }

    /// Writes any pending save now. Call when the app quits or goes to the
    /// background, where it may be ended without further notice.
    public func flush() {
        file?.saveNow(store.tasks)
    }

    /// Asks iCloud for changes, for when the app comes to the front.
    public func fetchChanges() {
        sync?.fetchChanges()
    }
}

import SwiftUI
import CookieCore
import CookieSync

@main
struct CookieApp: App {
    @State private var store: TaskStore
    @AppStorage("insertAtTop") private var insertAtTop = false

    init() {
        let environment = ProcessInfo.processInfo.environment
        // COOKIE_SAMPLE_DATA=1 runs on the prototype's sample tasks, in
        // memory only, so trying things out never touches saved tasks.
        if environment["COOKIE_SAMPLE_DATA"] == "1" {
            _store = State(initialValue: .sample())
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
        if let sync {
            sync.start()
            Self.observePushesAndActivation(for: sync)
        }

        // Flush a pending save so a change made just before quitting lands.
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak store] _ in
            MainActor.assumeIsolated {
                if let store { file.saveNow(store.tasks) }
            }
        }
        _store = State(initialValue: store)
    }

    /// Registers for the silent pushes CloudKit sends when another device
    /// changes something (the sync engine picks them up itself), and checks
    /// for changes whenever the app comes to the front, in case one was
    /// missed.
    private static func observePushesAndActivation(for sync: CloudSync) {
        let center = NotificationCenter.default
        _ = center.addObserver(
            forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { NSApplication.shared.registerForRemoteNotifications() }
        }
        _ = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { sync.fetchChanges() }
        }
    }

    var body: some Scene {
        Window("Cookie", id: "main") {
            MainWindowView(store: store)
                .environment(store)
                .tint(.cookieAccent)
                .onAppear { store.insertion = insertAtTop ? .top : .bottom }
                .onChange(of: insertAtTop) { _, top in store.insertion = top ? .top : .bottom }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 360, height: 680)

        Settings {
            SettingsView()
                .tint(.cookieAccent)
        }
    }
}

struct SettingsView: View {
    @AppStorage("insertAtTop") private var insertAtTop = false

    var body: some View {
        Form {
            Picker("Add new tasks at the", selection: $insertAtTop) {
                Text("bottom").tag(false)
                Text("top").tag(true)
            }
            .pickerStyle(.radioGroup)
        }
        .padding(20)
        .frame(width: 320)
    }
}


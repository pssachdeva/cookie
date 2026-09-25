import SwiftUI
import CookieCore

@main
struct CookieApp: App {
    @State private var store: TaskStore
    @AppStorage("insertAtTop") private var insertAtTop = false

    init() {
        // COOKIE_SAMPLE_DATA=1 runs on the prototype's sample tasks, in
        // memory only, so trying things out never touches saved tasks.
        if ProcessInfo.processInfo.environment["COOKIE_SAMPLE_DATA"] == "1" {
            _store = State(initialValue: .sample())
            return
        }
        let file = TaskFile(url: TaskFile.defaultURL())
        let store = TaskStore(tasks: file.load())
        store.onChange = { [weak store] _ in
            guard let store else { return }
            file.scheduleSave { store.tasks }
        }
        store.purgeDeleted(olderThan: TaskFile.deletedRetention)
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

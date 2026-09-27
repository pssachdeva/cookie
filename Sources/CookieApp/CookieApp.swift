import SwiftUI
import CookieCore
import CookieUI

@main
struct CookieApp: App {
    @State private var store: TaskStore
    @AppStorage("insertAtTop") private var insertAtTop = false

    init() {
        let model = CookieModel()
        _store = State(initialValue: model.store)

        let center = NotificationCenter.default
        // Flush a pending save so a change made just before quitting lands.
        _ = center.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { model.flush() }
        }
        guard model.sync != nil else { return }
        // Register for the silent pushes CloudKit sends when another device
        // changes something (the sync engine picks them up itself), and check
        // for changes whenever the app comes to the front, in case one was
        // missed.
        _ = center.addObserver(
            forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { NSApplication.shared.registerForRemoteNotifications() }
        }
        _ = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { model.fetchChanges() }
        }
    }

    var body: some Scene {
        // With the menu bar item present, closing this window leaves the app
        // running; Command-Q quits both.
        Window("Cookie", id: "main") {
            MainWindowView(store: store)
                .environment(store)
                .tint(.cookieAccent)
                .onChange(of: insertAtTop, initial: true, applyInsertion)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 360, height: 680)

        MenuBarExtra {
            MenuBarView(store: store)
                .environment(store)
                .tint(.cookieAccent)
                .onChange(of: insertAtTop, initial: true, applyInsertion)
        } label: {
            Image(nsImage: .cookieMenuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .tint(.cookieAccent)
                .onChange(of: insertAtTop, initial: true, applyInsertion)
        }
    }

    private func applyInsertion(_: Bool, _ top: Bool) {
        store.insertion = top ? .top : .bottom
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


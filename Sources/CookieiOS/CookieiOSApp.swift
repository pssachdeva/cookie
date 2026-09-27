import SwiftUI
import UIKit
import CookieCore
import CookieUI

@main
struct CookieiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = CookieModel()
    @AppStorage("insertAtTop") private var insertAtTop = false

    var body: some Scene {
        WindowGroup {
            DayPlannerView(store: model.store)
                .environment(model.store)
                .tint(.cookieAccent)
                .onChange(of: insertAtTop, initial: true) { _, top in
                    model.store.insertion = top ? .top : .bottom
                }
                .task {
                    // Silent pushes from CloudKit when another device changes
                    // something; the sync engine picks them up itself.
                    if model.sync != nil {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // iOS can end a backgrounded app without notice, so write
                // any pending save now.
                model.flush()
            case .active:
                model.fetchChanges()
            default:
                break
            }
        }
    }
}

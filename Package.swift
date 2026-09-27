// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Cookie",
    platforms: [.macOS("15.0"), .iOS("18.0")],
    products: [
        .executable(name: "CookieApp", targets: ["CookieApp"]),
        .library(name: "CookieCore", targets: ["CookieCore"]),
        .library(name: "CookieSync", targets: ["CookieSync"]),
        .library(name: "CookieUI", targets: ["CookieUI"]),
    ],
    targets: [
        // Platform-independent task model, calendar math, store, and saving.
        .target(name: "CookieCore"),
        // iCloud sync through CloudKit. Inactive unless the app is signed
        // with the iCloud entitlement (the Xcode project build).
        .target(name: "CookieSync", dependencies: ["CookieCore"]),
        // The SwiftUI calendar and checklist, shared by the Mac and iPhone
        // apps, and the model that loads, saves, and syncs their tasks.
        .target(name: "CookieUI", dependencies: ["CookieCore", "CookieSync"]),
        // The Mac app: window, menu bar panel, and settings. The iPhone app
        // lives in Sources/CookieiOS and is built by Cookie.xcodeproj.
        .executableTarget(name: "CookieApp", dependencies: ["CookieCore", "CookieUI"]),
        .testTarget(name: "CookieCoreTests", dependencies: ["CookieCore"]),
        .testTarget(name: "CookieSyncTests", dependencies: ["CookieSync"]),
    ]
)

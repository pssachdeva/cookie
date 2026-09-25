// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Cookie",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "CookieApp", targets: ["CookieApp"]),
        .library(name: "CookieCore", targets: ["CookieCore"]),
        .library(name: "CookieSync", targets: ["CookieSync"]),
    ],
    targets: [
        // Platform-independent task model, calendar math, store, and saving.
        .target(name: "CookieCore"),
        // iCloud sync through CloudKit. Inactive unless the app is signed
        // with the iCloud entitlement (the Xcode project build).
        .target(name: "CookieSync", dependencies: ["CookieCore"]),
        // The Mac app: SwiftUI window, calendar, and checklist.
        .executableTarget(name: "CookieApp", dependencies: ["CookieCore", "CookieSync"]),
        .testTarget(name: "CookieCoreTests", dependencies: ["CookieCore"]),
        .testTarget(name: "CookieSyncTests", dependencies: ["CookieSync"]),
    ]
)

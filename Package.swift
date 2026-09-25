// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Cookie",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "CookieApp", targets: ["CookieApp"]),
        .library(name: "CookieCore", targets: ["CookieCore"]),
    ],
    targets: [
        // Platform-independent task model, calendar math, and in-memory store.
        .target(name: "CookieCore"),
        // The Mac app: SwiftUI window, calendar, and checklist.
        .executableTarget(name: "CookieApp", dependencies: ["CookieCore"]),
        .testTarget(name: "CookieCoreTests", dependencies: ["CookieCore"]),
    ]
)

// swift-tools-version:5.9
// Perch: a Dynamic Island for Shabd's MacBook, sized around his camera cover.
import PackageDescription

let package = Package(
    name: "Perch",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Built-in updater. Keep this pinned to the same version CI downloads sign_update from.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .executableTarget(
            name: "Perch",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Perch",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("EventKit"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreMediaIO"),
                .linkedFramework("IOKit"),
                .linkedFramework("Network"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ]
)

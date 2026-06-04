// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LanGuardFeature",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "LanGuardFeature",
            targets: ["LanGuardFeature"]
        ),
    ],
    targets: [
        .target(
            name: "LanGuardFeature",
            // Swift 5 language mode — avoids Swift 6 strict-concurrency friction
            // with C callbacks (SCDynamicStore), AppKit observers, ObservableObject.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "LanGuardFeatureTests",
            dependencies: [
                "LanGuardFeature"
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

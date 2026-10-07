// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
// 5.9 keeps the default Swift-5 language mode (no Swift-6 strict concurrency) and builds on
// the stock Xcode shipped with macOS 14 CI runners.

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
            resources: [
                .copy("Resources/languard-net.sh"),
                .copy("Resources/com.roypadina.languard-net.plist"),
            ]
        ),
        .testTarget(
            name: "LanGuardFeatureTests",
            dependencies: ["LanGuardFeature"]
        ),
    ]
)

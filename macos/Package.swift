// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TextSyncMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TextSyncMac", targets: ["TextSyncMac"])
    ],
    targets: [
        .executableTarget(
            name: "TextSyncMac",
            path: "Sources/TextSyncMac"
        )
    ]
)

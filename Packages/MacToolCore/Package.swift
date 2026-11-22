// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MacToolCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MacToolCore",
            targets: ["MacToolCore"]
        ),
    ],
    targets: [
        .target(
            name: "MacToolCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "MacToolCoreTests",
            dependencies: ["MacToolCore"],
            resources: [
                .copy("Fixtures"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
    ]
)

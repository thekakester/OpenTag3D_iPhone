// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OpenTag3DKit",
    products: [
        .library(
            name: "OpenTag3DKit",
            targets: ["OpenTag3DKit"]
        )
    ],
    targets: [
        .target(
            name: "OpenTag3DKit",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "OpenTag3DKitTests",
            dependencies: ["OpenTag3DKit"]
        )
    ]
)

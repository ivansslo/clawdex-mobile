// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ClawdexDesktop",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ClawdexDesktop", targets: ["ClawdexDesktop"])
    ],
    targets: [
        .executableTarget(
            name: "ClawdexDesktop",
            resources: [
                .process("Resources")
            ]
        )
    ]
)

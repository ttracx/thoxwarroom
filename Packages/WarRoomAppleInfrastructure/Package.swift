// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "WarRoomAppleInfrastructure",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "WarRoomAppleInfrastructure",
            targets: ["WarRoomAppleInfrastructure"]
        ),
    ],
    dependencies: [
        .package(path: "../WarRoomCore"),
    ],
    targets: [
        .target(
            name: "WarRoomAppleInfrastructure",
            dependencies: ["WarRoomCore"]
        ),
        .testTarget(
            name: "WarRoomAppleInfrastructureTests",
            dependencies: ["WarRoomAppleInfrastructure", "WarRoomCore"]
        ),
    ],
    swiftLanguageVersions: [.v5]
)

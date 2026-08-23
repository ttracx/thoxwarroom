// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "WarRoomCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "WarRoomCore", targets: ["WarRoomCore"]),
    ],
    targets: [
        .target(name: "WarRoomCore"),
        .testTarget(
            name: "WarRoomCoreTests",
            dependencies: ["WarRoomCore"]
        ),
    ],
    swiftLanguageVersions: [.v5]
)

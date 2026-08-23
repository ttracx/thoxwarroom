// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "WarRoomOpenWebUI",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "WarRoomOpenWebUI", targets: ["WarRoomOpenWebUI"]),
    ],
    dependencies: [
        .package(path: "../WarRoomCore"),
    ],
    targets: [
        .target(
            name: "WarRoomOpenWebUI",
            dependencies: ["WarRoomCore"]
        ),
        .testTarget(
            name: "WarRoomOpenWebUITests",
            dependencies: ["WarRoomOpenWebUI", "WarRoomCore"],
            resources: [.process("Fixtures")]
        ),
    ],
    swiftLanguageVersions: [.v5]
)

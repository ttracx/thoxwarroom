// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "WarRoomHermes",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "WarRoomHermes", targets: ["WarRoomHermes"]),
    ],
    dependencies: [
        .package(path: "../WarRoomCore"),
    ],
    targets: [
        .target(
            name: "WarRoomHermes",
            dependencies: ["WarRoomCore"]
        ),
        .testTarget(
            name: "WarRoomHermesTests",
            dependencies: ["WarRoomHermes", "WarRoomCore"],
            resources: [.process("Fixtures")]
        ),
    ],
    swiftLanguageVersions: [.v5]
)

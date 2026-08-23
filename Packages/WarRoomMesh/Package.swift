// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "WarRoomMesh",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "WarRoomMesh", targets: ["WarRoomMesh"]),
    ],
    dependencies: [
        .package(path: "../WarRoomCore"),
    ],
    targets: [
        .target(
            name: "WarRoomMesh",
            dependencies: ["WarRoomCore"]
        ),
        .testTarget(
            name: "WarRoomMeshTests",
            dependencies: ["WarRoomMesh", "WarRoomCore"],
            resources: [.process("Fixtures")]
        ),
    ],
    swiftLanguageVersions: [.v5]
)

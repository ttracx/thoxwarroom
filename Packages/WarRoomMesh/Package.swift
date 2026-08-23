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
        .executable(
            name: "mesh-contract-evidence",
            targets: ["MeshContractEvidenceTool"]
        ),
    ],
    dependencies: [
        .package(path: "../WarRoomCore"),
    ],
    targets: [
        .target(
            name: "WarRoomMesh",
            dependencies: ["WarRoomCore"]
        ),
        .target(name: "MeshContractEvidence"),
        .executableTarget(
            name: "MeshContractEvidenceTool",
            dependencies: ["MeshContractEvidence"]
        ),
        .testTarget(
            name: "WarRoomMeshTests",
            dependencies: ["WarRoomMesh", "WarRoomCore", "MeshContractEvidence"],
            resources: [.process("Fixtures")]
        ),
    ],
    swiftLanguageVersions: [.v5]
)

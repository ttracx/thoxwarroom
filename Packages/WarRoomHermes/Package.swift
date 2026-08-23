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
        .executable(
            name: "hermes-contract-evidence",
            targets: ["HermesContractEvidenceTool"]
        ),
    ],
    dependencies: [
        .package(path: "../WarRoomCore"),
    ],
    targets: [
        .target(
            name: "WarRoomHermes",
            dependencies: ["WarRoomCore"]
        ),
        .target(name: "HermesContractEvidence"),
        .executableTarget(
            name: "HermesContractEvidenceTool",
            dependencies: ["HermesContractEvidence"]
        ),
        .testTarget(
            name: "WarRoomHermesTests",
            dependencies: ["WarRoomHermes", "WarRoomCore", "HermesContractEvidence"],
            resources: [.process("Fixtures")]
        ),
    ],
    swiftLanguageVersions: [.v5]
)

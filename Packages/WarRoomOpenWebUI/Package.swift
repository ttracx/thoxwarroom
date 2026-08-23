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
        .executable(
            name: "openwebui-contract-evidence",
            targets: ["OpenWebUIContractEvidenceTool"]
        ),
    ],
    dependencies: [
        .package(path: "../WarRoomCore"),
    ],
    targets: [
        .target(
            name: "WarRoomOpenWebUI",
            dependencies: ["WarRoomCore"]
        ),
        .target(
            name: "OpenWebUIContractEvidence"
        ),
        .executableTarget(
            name: "OpenWebUIContractEvidenceTool",
            dependencies: ["OpenWebUIContractEvidence"]
        ),
        .testTarget(
            name: "WarRoomOpenWebUITests",
            dependencies: [
                "WarRoomOpenWebUI",
                "WarRoomCore",
                "OpenWebUIContractEvidence",
            ],
            resources: [.process("Fixtures")]
        ),
    ],
    swiftLanguageVersions: [.v5]
)

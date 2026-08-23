import Foundation
import XCTest
import WarRoomAppleInfrastructure
import WarRoomCore
@testable import ThoxWarRoom

@MainActor
final class WorkspaceBrowserModelTests: XCTestCase {
    func testLoadsExplicitEmptyDirectoryStateWithRootProvenance() async {
        let directory = WorkspaceBrowserDirectory(
            rootDisplayPath: "/operator/root",
            relativePath: "",
            entries: [],
            isTruncated: false
        )
        let service = WorkspaceBrowserServiceStub(directory: directory)
        let model = WorkspaceBrowserModel(service: service)

        model.loadRoot()
        await model.waitForCurrentOperation()

        XCTAssertEqual(model.rootDisplayPath, "/operator/root")
        XCTAssertEqual(model.phase, .directory(directory))
        let listedPaths = await service.listedPaths()
        XCTAssertEqual(listedPaths, [""])
        XCTAssertTrue(model.canRefresh)

        model.refreshCurrentDirectory()
        await model.waitForCurrentOperation()
        let refreshedPaths = await service.listedPaths()
        XCTAssertEqual(refreshedPaths, ["", ""])
    }

    func testOpensDirectoryAndReturnsToParentUsingRelativePathsOnly() async {
        let child = WorkspaceBrowserEntry(
            name: "Child",
            relativePath: "Child",
            kind: .directory,
            byteCount: nil
        )
        let root = WorkspaceBrowserDirectory(
            rootDisplayPath: "/root",
            relativePath: "",
            entries: [child],
            isTruncated: false
        )
        let nested = WorkspaceBrowserDirectory(
            rootDisplayPath: "/root",
            relativePath: "Child",
            entries: [],
            isTruncated: false
        )
        let service = WorkspaceBrowserServiceStub(directory: root, directories: ["Child": nested])
        let model = WorkspaceBrowserModel(service: service)

        model.loadRoot()
        await model.waitForCurrentOperation()
        model.open(child)
        await model.waitForCurrentOperation()
        XCTAssertEqual(model.phase, .directory(nested))
        model.goToParent()
        await model.waitForCurrentOperation()

        XCTAssertEqual(model.phase, .directory(root))
        let listedPaths = await service.listedPaths()
        XCTAssertEqual(listedPaths, ["", "Child", ""])
    }

    func testPreviewsTextAndCanReturnWithoutRereadingDirectory() async {
        let file = WorkspaceBrowserEntry(
            name: "note.txt",
            relativePath: "note.txt",
            kind: .file,
            byteCount: 5
        )
        let directory = WorkspaceBrowserDirectory(
            rootDisplayPath: "/root",
            relativePath: "",
            entries: [file],
            isTruncated: false
        )
        let preview = WorkspaceTextPreview(
            rootDisplayPath: "/root",
            relativePath: "note.txt",
            text: "hello",
            byteCount: 5
        )
        let service = WorkspaceBrowserServiceStub(directory: directory, previews: ["note.txt": preview])
        let model = WorkspaceBrowserModel(service: service)

        model.loadRoot()
        await model.waitForCurrentOperation()
        model.open(file)
        await model.waitForCurrentOperation()

        XCTAssertEqual(model.phase, .preview(preview, directory: directory))
        model.closePreview()
        XCTAssertEqual(model.phase, .directory(directory))
        let previewedPaths = await service.previewedPaths()
        XCTAssertEqual(previewedPaths, ["note.txt"])
    }

    func testSymlinkEntryFailsClosedWithoutCallingService() async {
        let entry = WorkspaceBrowserEntry(
            name: "escape",
            relativePath: "escape",
            kind: .symbolicLinkBlocked,
            byteCount: nil
        )
        let directory = WorkspaceBrowserDirectory(
            rootDisplayPath: "/root",
            relativePath: "",
            entries: [entry],
            isTruncated: false
        )
        let service = WorkspaceBrowserServiceStub(directory: directory)
        let model = WorkspaceBrowserModel(service: service)
        model.loadRoot()
        await model.waitForCurrentOperation()

        model.open(entry)

        XCTAssertEqual(
            model.phase,
            .failed(
                "This symbolic link is blocked because it could leave the selected root.",
                lastDirectory: directory
            )
        )
        let previewedPaths = await service.previewedPaths()
        XCTAssertEqual(previewedPaths, [])
    }

    func testPreviewErrorIsSanitizedAndDoesNotExposePath() async {
        let sensitivePath = "client-secret/private.txt"
        let file = WorkspaceBrowserEntry(
            name: "private.txt",
            relativePath: sensitivePath,
            kind: .file,
            byteCount: 100
        )
        let directory = WorkspaceBrowserDirectory(
            rootDisplayPath: "/root",
            relativePath: "client-secret",
            entries: [file],
            isTruncated: false
        )
        let service = WorkspaceBrowserServiceStub(
            directory: directory,
            previewError: .previewTooLarge(limit: 8)
        )
        let model = WorkspaceBrowserModel(service: service)
        model.loadRoot()
        await model.waitForCurrentOperation()

        model.open(file)
        await model.waitForCurrentOperation()

        guard case .failed(let message, let lastDirectory) = model.phase else {
            return XCTFail("Expected failure")
        }
        XCTAssertEqual(message, "This file exceeds the 8-byte local preview limit.")
        XCTAssertFalse(message.contains(sensitivePath))
        XCTAssertEqual(lastDirectory, directory)
    }

    func testBrowserEligibilityDependsOnlyOnLocalBoundary() throws {
        XCTAssertTrue(try profile(boundary: .localMachine).supportsLocalWorkspaceBrowser)
        XCTAssertFalse(try profile(boundary: .privateNetwork).supportsLocalWorkspaceBrowser)
        XCTAssertFalse(try profile(boundary: .hosted).supportsLocalWorkspaceBrowser)
    }

    private func profile(boundary: NetworkBoundary) throws -> WorkspaceProfile {
        let endpointString: String
        let grant: HostedAccessAuthorization
        switch boundary {
        case .localMachine:
            endpointString = "http://localhost:8080"
            grant = .denied
        case .privateNetwork:
            endpointString = "https://provider.internal"
            grant = .denied
        case .hosted:
            endpointString = "https://provider.example"
            grant = .granted
        }
        let endpoint = try EndpointValidator.validate(
            endpointString,
            declaredBoundary: boundary,
            hostedAccess: grant,
            policy: WorkspaceProviderKind.openWebUI.endpointPolicy
        )
        return try WorkspaceProfile(
            displayName: "Browser eligibility",
            endpoint: endpoint,
            provider: WorkspaceProviderKind.openWebUI.descriptor
        )
    }
}

@MainActor
final class WorkspaceCommandActionTests: XCTestCase {
    func testCommandCarriesVisibleLabelAndInvokesOnlyExplicitAction() {
        var invocationCount = 0
        let command = WorkspaceCommandAction("Refresh Visible Surface") {
            invocationCount += 1
        }

        XCTAssertEqual(command.title, "Refresh Visible Surface")
        XCTAssertEqual(invocationCount, 0)
        command.perform()
        XCTAssertEqual(invocationCount, 1)
    }
}

private actor WorkspaceBrowserServiceStub: WorkspaceBrowserServicing {
    nonisolated let rootDisplayPath: String
    private let rootDirectory: WorkspaceBrowserDirectory
    private let directories: [String: WorkspaceBrowserDirectory]
    private let previews: [String: WorkspaceTextPreview]
    private let previewError: WorkspaceBrowserError?
    private var listCalls: [String] = []
    private var previewCalls: [String] = []

    init(
        directory: WorkspaceBrowserDirectory,
        directories: [String: WorkspaceBrowserDirectory] = [:],
        previews: [String: WorkspaceTextPreview] = [:],
        previewError: WorkspaceBrowserError? = nil
    ) {
        self.rootDisplayPath = directory.rootDisplayPath
        self.rootDirectory = directory
        self.directories = directories
        self.previews = previews
        self.previewError = previewError
    }

    func list(relativePath: String) async throws -> WorkspaceBrowserDirectory {
        listCalls.append(relativePath)
        if relativePath.isEmpty { return rootDirectory }
        guard let directory = directories[relativePath] else {
            throw WorkspaceBrowserError.itemUnavailable
        }
        return directory
    }

    func preview(relativePath: String) async throws -> WorkspaceTextPreview {
        previewCalls.append(relativePath)
        if let previewError { throw previewError }
        guard let preview = previews[relativePath] else {
            throw WorkspaceBrowserError.itemUnavailable
        }
        return preview
    }

    func listedPaths() -> [String] { listCalls }
    func previewedPaths() -> [String] { previewCalls }
}

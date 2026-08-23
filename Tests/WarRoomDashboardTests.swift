import Foundation
import XCTest
import WarRoomCore
import WarRoomMesh
@testable import ThoxWarRoom

@MainActor
final class WarRoomDashboardModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_777_000_100)

    func testLoadMapsFreshAndEmptySnapshots() async throws {
        let readySnapshot = try snapshot(devices: [device()], fetchedAt: now)
        let readyModel = WarRoomDashboardModel(
            profile: try profile(),
            meshID: meshID(),
            service: DashboardServiceStub(result: .success(readySnapshot)),
            now: { self.now }
        )
        readyModel.load()
        XCTAssertEqual(readyModel.state, .loading)
        await readyModel.waitForCurrentLoad()
        XCTAssertEqual(readyModel.state, .ready(readySnapshot))

        let emptySnapshot = try snapshot(fetchedAt: now)
        let emptyModel = WarRoomDashboardModel(
            profile: try profile(),
            meshID: meshID(),
            service: DashboardServiceStub(result: .success(emptySnapshot)),
            now: { self.now }
        )
        emptyModel.load()
        await emptyModel.waitForCurrentLoad()
        XCTAssertEqual(emptyModel.state, .empty(emptySnapshot))
    }

    func testLoadMapsStaleAndPartialFailureStates() async throws {
        let stale = try snapshot(
            devices: [device()],
            fetchedAt: now.addingTimeInterval(-31)
        )
        let staleModel = WarRoomDashboardModel(
            profile: try profile(),
            meshID: meshID(),
            service: DashboardServiceStub(result: .success(stale)),
            now: { self.now }
        )
        staleModel.load()
        await staleModel.waitForCurrentLoad()
        XCTAssertEqual(staleModel.state, .stale(stale))

        let partial = try snapshot(
            devices: [device()],
            fetchedAt: now,
            failures: [.init(section: .topology, reason: .offline)]
        )
        let partialModel = WarRoomDashboardModel(
            profile: try profile(),
            meshID: meshID(),
            service: DashboardServiceStub(result: .success(partial)),
            now: { self.now }
        )
        partialModel.load()
        await partialModel.waitForCurrentLoad()
        XCTAssertEqual(partialModel.state, .partialFailure(partial))
    }

    func testOfflineAndUnknownErrorsNeverExposeSensitiveIdentifiers() async throws {
        let offline = WarRoomDashboardModel(
            profile: try profile(),
            meshID: meshID(),
            service: DashboardServiceStub(
                result: .failure(WarRoomDashboardServiceError.providerOffline)
            )
        )
        offline.load()
        await offline.waitForCurrentLoad()
        guard case .offline(let offlineMessage) = offline.state else {
            return XCTFail("Expected offline state")
        }
        XCTAssertFalse(offlineMessage.contains(meshValue))

        let unknown = WarRoomDashboardModel(
            profile: try profile(),
            meshID: meshID(),
            service: DashboardServiceStub(
                result: .failure(
                    DashboardTestError.sensitive("failed for \(meshValue) with private-token")
                )
            )
        )
        unknown.load()
        await unknown.waitForCurrentLoad()
        guard case .error(let errorMessage) = unknown.state else {
            return XCTFail("Expected error state")
        }
        XCTAssertFalse(errorMessage.contains(meshValue))
        XCTAssertFalse(errorMessage.contains("private-token"))
    }

    func testCancellationReturnsToIdleWithoutSurfacingFailure() async throws {
        let model = WarRoomDashboardModel(
            profile: try profile(),
            meshID: meshID(),
            service: DashboardServiceStub(result: .delayed)
        )
        model.load()
        XCTAssertEqual(model.state, .loading)
        model.cancel()
        await model.waitForCurrentLoad()
        XCTAssertEqual(model.state, .idle)
    }

    private var meshValue: String { "00000000-0000-0000-0000-000000000400" }

    private func meshID() -> MeshID {
        try! MeshID(validating: meshValue)
    }

    private func profile(
        provider: ProviderDescriptor = MeshProvider.descriptor
    ) throws -> WorkspaceProfile {
        try WorkspaceProfile(
            displayName: "Private War Room",
            endpoint: EndpointValidator.validate(
                "http://127.0.0.1",
                declaredBoundary: .localMachine
            ),
            provider: provider
        )
    }

    private func device() -> MeshDevice {
        MeshDevice(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
            meshID: meshID(),
            displayName: "Local Workstation",
            platform: "macOS",
            role: "operator",
            lastSeen: now
        )
    }

    private func snapshot(
        devices: [MeshDevice] = [],
        fetchedAt: Date,
        failures: [WarRoomDashboardSectionFailure] = []
    ) throws -> WarRoomDashboardSnapshot {
        WarRoomDashboardSnapshot(
            devices: devices,
            topology: MeshTopology(meshID: meshID(), nodes: [], edges: []),
            events: [],
            provenance: [
                MeshSnapshotMetadata(
                    meshID: meshID(),
                    fetchedAt: fetchedAt,
                    source: .adminConsole,
                    evidence: .currentSourceNotLiveVerified,
                    networkBoundary: .localMachine
                ),
            ],
            failures: failures
        )
    }
}

final class DefaultWarRoomDashboardServiceTests: XCTestCase {
    func testCapabilityGateStopsBeforeCredentialAndTransport() async throws {
        let vault = DashboardCredentialVault(credential: ProviderCredential(bytes: Data("secret".utf8)))
        let transport = DashboardTransport(mode: .success)
        let service = DefaultWarRoomDashboardService(credentialVault: vault, transport: transport)
        let mismatched = ProviderDescriptor(
            id: ProviderID(rawValue: "different-provider"),
            displayName: "Different Provider",
            capabilities: [.warRoomStatus]
        )

        do {
            _ = try await service.loadDashboard(
                for: try profile(provider: mismatched),
                meshID: meshID()
            )
            XCTFail("Expected capability rejection")
        } catch {
            XCTAssertEqual(error as? WarRoomDashboardServiceError, .unsupportedProvider)
        }
        let vaultReadCount = await vault.readCount()
        let transportCallCount = await transport.callCount()
        XCTAssertEqual(vaultReadCount, 0)
        XCTAssertEqual(transportCallCount, 0)
    }

    func testReadOnlyServiceLoadsAllSectionsWithCredentialAtRequestTime() async throws {
        let vault = DashboardCredentialVault(credential: ProviderCredential(bytes: Data("secret".utf8)))
        let transport = DashboardTransport(mode: .success)
        let service = DefaultWarRoomDashboardService(credentialVault: vault, transport: transport)

        let snapshot = try await service.loadDashboard(for: try profile(), meshID: meshID())

        XCTAssertEqual(snapshot.devices.map(\.displayName), ["Local Workstation"])
        XCTAssertEqual(snapshot.topology?.nodes.count, 1)
        XCTAssertEqual(snapshot.events.map(\.eventType), ["heartbeat"])
        XCTAssertEqual(snapshot.provenance.count, 3)
        XCTAssertTrue(snapshot.failures.isEmpty)
        let calls = await transport.calls()
        XCTAssertEqual(Set(calls.map(\.method)), [.get])
        XCTAssertEqual(Set(calls.map(\.path)), Set(MeshEndpoint.allDashboardPaths))
        XCTAssertTrue(calls.allSatisfy(\.hadCredential))
    }

    func testOneFailedSectionPreservesAvailableDataAsPartialFailure() async throws {
        let vault = DashboardCredentialVault(credential: ProviderCredential(bytes: Data("secret".utf8)))
        let service = DefaultWarRoomDashboardService(
            credentialVault: vault,
            transport: DashboardTransport(mode: .topologyUnavailable)
        )

        let snapshot = try await service.loadDashboard(for: try profile(), meshID: meshID())

        XCTAssertEqual(snapshot.devices.count, 1)
        XCTAssertNil(snapshot.topology)
        XCTAssertEqual(snapshot.events.count, 1)
        XCTAssertEqual(snapshot.provenance.count, 2)
        XCTAssertEqual(
            snapshot.failures,
            [.init(section: .topology, reason: .unavailable)]
        )
    }

    func testTotalTransportFailureIsRedactedOfflineError() async throws {
        let vault = DashboardCredentialVault(credential: ProviderCredential(bytes: Data("secret".utf8)))
        let service = DefaultWarRoomDashboardService(
            credentialVault: vault,
            transport: DashboardTransport(mode: .offlineWithSensitiveError)
        )

        do {
            _ = try await service.loadDashboard(for: try profile(), meshID: meshID())
            XCTFail("Expected offline error")
        } catch {
            XCTAssertEqual(error as? WarRoomDashboardServiceError, .providerOffline)
            XCTAssertFalse(error.localizedDescription.contains("private-token"))
            XCTAssertFalse(error.localizedDescription.contains(meshValue))
        }
    }

    private let meshValue = "00000000-0000-0000-0000-000000000400"

    private func meshID() -> MeshID { try! MeshID(validating: meshValue) }

    private func profile(
        provider: ProviderDescriptor = MeshProvider.descriptor
    ) throws -> WorkspaceProfile {
        try WorkspaceProfile(
            displayName: "Private War Room",
            endpoint: EndpointValidator.validate(
                "http://127.0.0.1",
                declaredBoundary: .localMachine
            ),
            provider: provider
        )
    }
}

private actor DashboardServiceStub: WarRoomDashboardServicing {
    enum Result {
        case success(WarRoomDashboardSnapshot)
        case failure(Error)
        case delayed
    }

    let result: Result

    init(result: Result) {
        self.result = result
    }

    func loadDashboard(
        for profile: WorkspaceProfile,
        meshID: MeshID
    ) async throws -> WarRoomDashboardSnapshot {
        switch result {
        case .success(let snapshot): return snapshot
        case .failure(let error): throw error
        case .delayed:
            try await Task.sleep(nanoseconds: 30_000_000_000)
            throw CancellationError()
        }
    }
}

private enum DashboardTestError: Error {
    case sensitive(String)
}

private actor DashboardCredentialVault: CredentialVault {
    private let storedCredential: ProviderCredential?
    private var reads = 0

    init(credential: ProviderCredential?) {
        storedCredential = credential
    }

    func credential(for workspaceID: WorkspaceID) -> ProviderCredential? {
        reads += 1
        return storedCredential
    }

    func store(_ credential: ProviderCredential, for workspaceID: WorkspaceID) {}
    func deleteCredential(for workspaceID: WorkspaceID) {}
    func readCount() -> Int { reads }
}

private actor DashboardTransport: ProviderTransport {
    enum Mode { case success, topologyUnavailable, offlineWithSensitiveError }

    struct Call: Sendable {
        let method: ProviderRequest.Method
        let path: String
        let hadCredential: Bool
    }

    private let mode: Mode
    private var recordedCalls: [Call] = []

    init(mode: Mode) { self.mode = mode }

    func send(
        _ request: ProviderRequest,
        to endpoint: ValidatedEndpoint,
        credential: ProviderCredential?
    ) throws -> ProviderResponse {
        recordedCalls.append(.init(
            method: request.method,
            path: request.relativePath,
            hadCredential: credential != nil
        ))
        if mode == .offlineWithSensitiveError {
            throw DashboardTestError.sensitive("private-token and 00000000-0000-0000-0000-000000000400")
        }
        if mode == .topologyUnavailable, request.relativePath == MeshEndpoint.topology.rawValue {
            return ProviderResponse(statusCode: 503, body: Data("private detail".utf8))
        }
        return ProviderResponse(statusCode: 200, body: responseBody(for: request.relativePath))
    }

    func calls() -> [Call] { recordedCalls }
    func callCount() -> Int { recordedCalls.count }

    private func responseBody(for path: String) -> Data {
        let meshID = "00000000-0000-0000-0000-000000000400"
        let deviceID = "00000000-0000-0000-0000-000000000401"
        switch path {
        case MeshEndpoint.devices.rawValue:
            return Data("""
            {"data":[{"id":"\(deviceID)","mesh_id":"\(meshID)","display_name":"Local Workstation","platform":"macOS","role":"operator","last_seen":"2026-08-23T12:00:00Z"}]}
            """.utf8)
        case MeshEndpoint.topology.rawValue:
            return Data("""
            {"mesh_id":"\(meshID)","nodes":[{"id":"\(deviceID)","display_name":"Local Workstation","role":"operator","platform":"macOS","last_seen":"2026-08-23T12:00:00Z"}],"edges":[]}
            """.utf8)
        case MeshEndpoint.events.rawValue:
            return Data("""
            {"mesh_id":"\(meshID)","count":1,"data":[{"id":"00000000-0000-0000-0000-000000000402","device_id":"\(deviceID)","event_type":"heartbeat","severity":"info","message":"private event detail","created_at":"2026-08-23T12:00:00Z"}]}
            """.utf8)
        default:
            return Data()
        }
    }
}

private extension MeshEndpoint {
    static var allDashboardPaths: [String] {
        [devices.rawValue, topology.rawValue, events.rawValue]
    }
}

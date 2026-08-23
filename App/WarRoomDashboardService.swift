import Foundation
import WarRoomAppleInfrastructure
import WarRoomCore
import WarRoomMesh

protocol WarRoomDashboardServicing: Sendable {
    func loadDashboard(
        for profile: WorkspaceProfile,
        meshID: MeshID
    ) async throws -> WarRoomDashboardSnapshot
}

/// Read-only dashboard service. It exposes no provider mutation operation.
struct DefaultWarRoomDashboardService: WarRoomDashboardServicing, Sendable {
    private let credentialVault: any CredentialVault
    private let transport: any ProviderTransport

    init(
        credentialVault: any CredentialVault = KeychainCredentialVault(),
        transport: any ProviderTransport = URLSessionProviderTransport()
    ) {
        self.credentialVault = credentialVault
        self.transport = transport
    }

    func loadDashboard(
        for profile: WorkspaceProfile,
        meshID: MeshID
    ) async throws -> WarRoomDashboardSnapshot {
        guard profile.provider.id == MeshProvider.descriptor.id,
              profile.provider.supports(.warRoomStatus),
              MeshProvider.descriptor.supports(.warRoomStatus) else {
            throw WarRoomDashboardServiceError.unsupportedProvider
        }

        let credential: ProviderCredential
        do {
            try Task.checkCancellation()
            guard let stored = try await credentialVault.credential(for: profile.id) else {
                throw WarRoomDashboardServiceError.credentialRequired
            }
            credential = stored
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as WarRoomDashboardServiceError {
            throw error
        } catch {
            throw WarRoomDashboardServiceError.credentialStoreUnavailable
        }

        let client = MeshClient(
            endpoint: profile.endpoint,
            transport: transport,
            credential: credential
        )

        async let devicesResult = Self.loadDevices(client: client, meshID: meshID)
        async let topologyResult = Self.loadTopology(client: client, meshID: meshID)
        async let eventsResult = Self.loadEvents(client: client, meshID: meshID)
        let results = try await (devicesResult, topologyResult, eventsResult)
        try Task.checkCancellation()

        var provenance: [MeshSnapshotMetadata] = []
        var failures: [WarRoomDashboardSectionFailure] = []
        let devices: [MeshDevice]
        switch results.0 {
        case .success(let snapshot):
            devices = snapshot.value.data
            provenance.append(snapshot.metadata)
        case .failure(let failure):
            devices = []
            failures.append(failure)
        }

        let topology: MeshTopology?
        switch results.1 {
        case .success(let snapshot):
            topology = snapshot.value
            provenance.append(snapshot.metadata)
        case .failure(let failure):
            topology = nil
            failures.append(failure)
        }

        let events: [MeshEvent]
        switch results.2 {
        case .success(let snapshot):
            events = snapshot.value.data
            provenance.append(snapshot.metadata)
        case .failure(let failure):
            events = []
            failures.append(failure)
        }

        guard !provenance.isEmpty else {
            throw Self.totalFailure(from: failures)
        }

        return WarRoomDashboardSnapshot(
            devices: devices,
            topology: topology,
            events: events,
            provenance: provenance,
            failures: failures
        )
    }

    private static func loadDevices(
        client: MeshClient,
        meshID: MeshID
    ) async throws -> DashboardSectionResult<MeshDevicesEnvelope> {
        do {
            return .success(try await client.devices(in: meshID))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .failure(sectionFailure(.devices, error: error))
        }
    }

    private static func loadTopology(
        client: MeshClient,
        meshID: MeshID
    ) async throws -> DashboardSectionResult<MeshTopology> {
        do {
            return .success(try await client.topology(for: meshID))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .failure(sectionFailure(.topology, error: error))
        }
    }

    private static func loadEvents(
        client: MeshClient,
        meshID: MeshID
    ) async throws -> DashboardSectionResult<MeshEventsEnvelope> {
        do {
            return .success(try await client.events(in: meshID))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .failure(sectionFailure(.events, error: error))
        }
    }

    private static func sectionFailure(
        _ section: WarRoomDashboardSection,
        error: Error
    ) -> WarRoomDashboardSectionFailure {
        let reason: WarRoomDashboardFailureReason
        guard let meshError = error as? MeshProviderError else {
            return WarRoomDashboardSectionFailure(section: section, reason: .unavailable)
        }
        switch meshError {
        case .transportFailure:
            reason = .offline
        case .authenticationRequired:
            reason = .authenticationRequired
        case .accessDenied:
            reason = .accessDenied
        case .decodingFailed, .contractViolation, .responseTooLarge:
            reason = .invalidResponse
        case .unsupportedCapability, .requestConstructionFailed, .notFound, .unexpectedStatus:
            reason = .unavailable
        }
        return WarRoomDashboardSectionFailure(section: section, reason: reason)
    }

    private static func totalFailure(
        from failures: [WarRoomDashboardSectionFailure]
    ) -> WarRoomDashboardServiceError {
        let reasons = Set(failures.map(\.reason))
        if reasons == [.offline] { return .providerOffline }
        if reasons.contains(.authenticationRequired) { return .authenticationRequired }
        if reasons.contains(.accessDenied) { return .accessDenied }
        return .unavailable
    }
}

private enum DashboardSectionResult<Value: Sendable>: Sendable {
    case success(MeshSnapshot<Value>)
    case failure(WarRoomDashboardSectionFailure)
}

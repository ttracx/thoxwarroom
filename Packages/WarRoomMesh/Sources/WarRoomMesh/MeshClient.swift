import Foundation
import WarRoomCore

/// Read-only client for current MeshStack admin-console status contracts.
public struct MeshClient: Sendable {
    private let endpoint: ValidatedEndpoint
    private let transport: any ProviderTransport
    private let credential: ProviderCredential?
    private let descriptor: ProviderDescriptor
    private let limits: MeshResponseLimits
    private let now: @Sendable () -> Date

    /// Creates a client without performing network access.
    public init(
        endpoint: ValidatedEndpoint,
        transport: any ProviderTransport,
        credential: ProviderCredential? = nil,
        descriptor: ProviderDescriptor = MeshProvider.descriptor,
        limits: MeshResponseLimits = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.endpoint = endpoint
        self.transport = transport
        self.credential = credential
        self.descriptor = descriptor
        self.limits = limits
        self.now = now
    }

    /// Fetches devices scoped to one mesh through the user-authenticated admin surface.
    public func devices(in meshID: MeshID) async throws -> MeshSnapshot<MeshDevicesEnvelope> {
        let envelope: MeshDevicesEnvelope = try await decodedResponse(
            for: .devices,
            queryItems: try meshQueryItems(meshID, endpoint: .devices)
        )
        try validate(envelope, requestedMeshID: meshID)
        return snapshot(envelope, meshID: meshID)
    }

    /// Fetches computed topology scoped to one mesh.
    public func topology(for meshID: MeshID) async throws -> MeshSnapshot<MeshTopology> {
        let topology: MeshTopology = try await decodedResponse(
            for: .topology,
            queryItems: try meshQueryItems(meshID, endpoint: .topology)
        )
        try validate(topology, requestedMeshID: meshID)
        return snapshot(topology, meshID: meshID)
    }

    /// Fetches bounded event history scoped to one mesh.
    public func events(
        in meshID: MeshID,
        limit: MeshEventLimit = .standard
    ) async throws -> MeshSnapshot<MeshEventsEnvelope> {
        let queryItems: [ProviderQueryItem]
        do {
            queryItems = [
                try ProviderQueryItem(name: "mesh_id", value: meshID.queryValue),
                try ProviderQueryItem(name: "limit", value: String(limit.rawValue)),
            ]
        } catch {
            throw MeshProviderError.requestConstructionFailed(endpoint: .events)
        }
        let envelope: MeshEventsEnvelope = try await decodedResponse(
            for: .events,
            queryItems: queryItems
        )
        try validate(envelope, requestedMeshID: meshID)
        return snapshot(envelope, meshID: meshID)
    }

    private func meshQueryItems(
        _ meshID: MeshID,
        endpoint: MeshEndpoint
    ) throws -> [ProviderQueryItem] {
        do {
            return [try ProviderQueryItem(name: "mesh_id", value: meshID.queryValue)]
        } catch {
            // A UUID is always an RFC 3986 unreserved component. Preserve a
            // typed package invariant if either representation changes.
            throw MeshProviderError.requestConstructionFailed(endpoint: endpoint)
        }
    }

    private func decodedResponse<Value: Decodable>(
        for meshEndpoint: MeshEndpoint,
        queryItems: [ProviderQueryItem]
    ) async throws -> Value {
        let body = try await responseBody(for: meshEndpoint, queryItems: queryItems)
        do {
            return try Self.makeDecoder().decode(Value.self, from: body)
        } catch {
            throw MeshProviderError.decodingFailed(endpoint: meshEndpoint)
        }
    }

    private func responseBody(
        for meshEndpoint: MeshEndpoint,
        queryItems: [ProviderQueryItem]
    ) async throws -> Data {
        guard descriptor.supports(.warRoomStatus) else {
            throw MeshProviderError.unsupportedCapability(.warRoomStatus)
        }

        let request: ProviderRequest
        do {
            request = try ProviderRequest(
                method: .get,
                relativePath: meshEndpoint.rawValue,
                queryItems: queryItems
            )
        } catch {
            throw MeshProviderError.requestConstructionFailed(endpoint: meshEndpoint)
        }

        let response: ProviderResponse
        do {
            try Task.checkCancellation()
            response = try await transport.send(
                request,
                to: endpoint,
                credential: credential
            )
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MeshProviderError.transportFailure(endpoint: meshEndpoint)
        }

        switch response.statusCode {
        case 200:
            break
        case 401:
            throw MeshProviderError.authenticationRequired(endpoint: meshEndpoint)
        case 403:
            throw MeshProviderError.accessDenied(endpoint: meshEndpoint)
        case 404:
            throw MeshProviderError.notFound(endpoint: meshEndpoint)
        default:
            throw MeshProviderError.unexpectedStatus(
                endpoint: meshEndpoint,
                statusCode: response.statusCode
            )
        }

        guard response.body.count <= limits.maximumResponseBytes else {
            throw MeshProviderError.responseTooLarge(
                endpoint: meshEndpoint,
                limit: limits.maximumResponseBytes,
                actual: response.body.count
            )
        }
        return response.body
    }

    private func snapshot<Value: Sendable>(
        _ value: Value,
        meshID: MeshID
    ) -> MeshSnapshot<Value> {
        MeshSnapshot(
            value: value,
            metadata: MeshSnapshotMetadata(
                meshID: meshID,
                fetchedAt: now(),
                source: .adminConsole,
                evidence: .currentSourceNotLiveVerified,
                networkBoundary: endpoint.boundary
            )
        )
    }

    private func validate(
        _ envelope: MeshDevicesEnvelope,
        requestedMeshID: MeshID
    ) throws {
        guard envelope.data.allSatisfy({ $0.meshID == requestedMeshID }) else {
            throw MeshProviderError.contractViolation(
                endpoint: .devices,
                violation: .meshIdentifierMismatch
            )
        }
        guard Set(envelope.data.map(\.id)).count == envelope.data.count else {
            throw MeshProviderError.contractViolation(
                endpoint: .devices,
                violation: .duplicateIdentifier
            )
        }
        guard envelope.data.allSatisfy({
            Self.hasText($0.displayName) && Self.hasText($0.platform) && Self.hasText($0.role)
        }) else {
            throw MeshProviderError.contractViolation(
                endpoint: .devices,
                violation: .blankRequiredField
            )
        }
    }

    private func validate(
        _ topology: MeshTopology,
        requestedMeshID: MeshID
    ) throws {
        guard topology.meshID == requestedMeshID else {
            throw MeshProviderError.contractViolation(
                endpoint: .topology,
                violation: .meshIdentifierMismatch
            )
        }
        let nodeIDs = Set(topology.nodes.map(\.id))
        guard nodeIDs.count == topology.nodes.count else {
            throw MeshProviderError.contractViolation(
                endpoint: .topology,
                violation: .duplicateIdentifier
            )
        }
        guard topology.nodes.allSatisfy({
            Self.hasText($0.displayName) && Self.hasText($0.platform) && Self.hasText($0.role)
        }) else {
            throw MeshProviderError.contractViolation(
                endpoint: .topology,
                violation: .blankRequiredField
            )
        }
        guard topology.edges.allSatisfy({ nodeIDs.contains($0.source) && nodeIDs.contains($0.target) }) else {
            throw MeshProviderError.contractViolation(
                endpoint: .topology,
                violation: .edgeReferencesUnknownNode
            )
        }
        guard topology.edges.allSatisfy({ edge in
            guard let latency = edge.roundTripMilliseconds else { return true }
            return latency.isFinite && latency >= 0
        }) else {
            throw MeshProviderError.contractViolation(
                endpoint: .topology,
                violation: .negativeRoundTripTime
            )
        }
    }

    private func validate(
        _ envelope: MeshEventsEnvelope,
        requestedMeshID: MeshID
    ) throws {
        guard envelope.meshID == requestedMeshID else {
            throw MeshProviderError.contractViolation(
                endpoint: .events,
                violation: .meshIdentifierMismatch
            )
        }
        guard envelope.count == envelope.data.count else {
            throw MeshProviderError.contractViolation(
                endpoint: .events,
                violation: .countMismatch
            )
        }
        guard Set(envelope.data.map(\.id)).count == envelope.data.count else {
            throw MeshProviderError.contractViolation(
                endpoint: .events,
                violation: .duplicateIdentifier
            )
        }
        guard envelope.data.allSatisfy({ Self.hasText($0.eventType) && Self.hasText($0.severity) }) else {
            throw MeshProviderError.contractViolation(
                endpoint: .events,
                violation: .blankRequiredField
            )
        }
    }

    private static func hasText(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }

            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO 8601 timestamp"
            )
        }
        return decoder
    }
}

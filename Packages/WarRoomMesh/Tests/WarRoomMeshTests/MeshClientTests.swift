import Foundation
import XCTest
import WarRoomCore
@testable import WarRoomMesh

final class MeshClientTests: XCTestCase {
    private let syntheticMeshValue = "00000000-0000-0000-0000-000000000100"
    private let capturedAt = Date(timeIntervalSince1970: 1_777_000_000)

    func testEndpointPathsAndCapabilitiesAreReadOnlyAndCaptured() {
        XCTAssertEqual(MeshEndpoint.devices.rawValue, "/api/admin/console/devices")
        XCTAssertEqual(MeshEndpoint.topology.rawValue, "/api/admin/console/topology")
        XCTAssertEqual(MeshEndpoint.events.rawValue, "/api/admin/console/events")
        XCTAssertEqual(MeshProvider.descriptor.capabilities, [.warRoomStatus])
        XCTAssertFalse(MeshProvider.descriptor.supports(.modelCatalog))
        XCTAssertFalse(MeshProvider.descriptor.supports(.scopedApprovals))
    }

    func testValidatesMeshUUIDAndEventLimitsBeforeUse() throws {
        XCTAssertEqual(try MeshID(validating: syntheticMeshValue).queryValue, syntheticMeshValue)
        XCTAssertEqual(try MeshEventLimit(rawValue: 1).rawValue, 1)
        XCTAssertEqual(try MeshEventLimit(rawValue: 500).rawValue, 500)

        for value in ["", "not-a-uuid", " 00000000-0000-0000-0000-000000000100"] {
            XCTAssertThrowsError(try MeshID(validating: value)) { error in
                XCTAssertEqual(error as? MeshInputError, .invalidMeshIdentifier)
            }
        }
        for value in [0, 501] {
            XCTAssertThrowsError(try MeshEventLimit(rawValue: value)) { error in
                XCTAssertEqual(error as? MeshInputError, .invalidEventLimit(value))
            }
        }
    }

    func testDevicesUseReadOnlyScopedQueryAndDecodeSyntheticFixture() async throws {
        let transport = RecordingTransport(response: .init(
            statusCode: 200,
            body: try fixtureData(named: "devices.synthetic")
        ))
        let client = try makeClient(transport: transport)

        let snapshot = try await client.devices(in: meshID())

        XCTAssertEqual(snapshot.value.data.count, 2)
        XCTAssertEqual(snapshot.value.data.first?.displayName, "Synthetic Mac")
        let expectedMeshID = try meshID()
        XCTAssertEqual(snapshot.metadata.meshID, expectedMeshID)
        XCTAssertEqual(snapshot.metadata.fetchedAt, capturedAt)
        XCTAssertEqual(snapshot.metadata.source, .adminConsole)
        XCTAssertEqual(snapshot.metadata.evidence, .currentSourceNotLiveVerified)
        XCTAssertEqual(snapshot.metadata.networkBoundary, .hosted)

        let calls = await transport.calls()
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.request.method, .get)
        XCTAssertEqual(call.request.relativePath, "/api/admin/console/devices")
        XCTAssertEqual(call.request.queryItems, [
            try ProviderQueryItem(name: "mesh_id", value: syntheticMeshValue),
        ])
        XCTAssertNil(call.request.body)
        XCTAssertTrue(call.hadCredential)
    }

    func testTopologyDecodesNodesEdgesAndFractionalLatency() async throws {
        let client = try makeClient(transport: RecordingTransport(response: .init(
            statusCode: 200,
            body: try fixtureData(named: "topology.synthetic")
        )))

        let snapshot = try await client.topology(for: meshID())

        XCTAssertEqual(snapshot.value.nodes.count, 2)
        XCTAssertEqual(snapshot.value.edges.count, 1)
        XCTAssertEqual(snapshot.value.edges.first?.roundTripMilliseconds, 7.5)
        XCTAssertTrue(snapshot.value.edges.first?.tunnelActive == true)
    }

    func testEventsUseValidatedLimitAndDecodeFractionalTimestamp() async throws {
        let transport = RecordingTransport(response: .init(
            statusCode: 200,
            body: try fixtureData(named: "events.synthetic")
        ))
        let client = try makeClient(transport: transport)

        let snapshot = try await client.events(
            in: meshID(),
            limit: try MeshEventLimit(rawValue: 500)
        )

        XCTAssertEqual(snapshot.value.count, 2)
        XCTAssertEqual(snapshot.value.data.count, 2)
        let firstCreatedAt = try XCTUnwrap(snapshot.value.data.first?.createdAt)
        let lastCreatedAt = try XCTUnwrap(snapshot.value.data.last?.createdAt)
        XCTAssertEqual(lastCreatedAt.timeIntervalSince(firstCreatedAt), 1.25, accuracy: 0.001)
        let calls = await transport.calls()
        XCTAssertEqual(try XCTUnwrap(calls.first).request.queryItems, [
            try ProviderQueryItem(name: "mesh_id", value: syntheticMeshValue),
            try ProviderQueryItem(name: "limit", value: "500"),
        ])
    }

    func testCapabilityGatePreventsTransportCall() async throws {
        let transport = RecordingTransport(response: .init(statusCode: 200, body: Data()))
        let descriptor = ProviderDescriptor(
            id: ProviderID(rawValue: "disabled-mesh"),
            displayName: "Disabled Mesh",
            capabilities: []
        )
        let client = try makeClient(transport: transport, descriptor: descriptor)

        await XCTAssertThrowsErrorAsync(try await client.devices(in: meshID())) { error in
            XCTAssertEqual(error as? MeshProviderError, .unsupportedCapability(.warRoomStatus))
        }
        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 0)
    }

    func testMapsNonSensitiveHTTPFailuresWithoutDecodingBody() async throws {
        let cases: [(Int, MeshProviderError)] = [
            (401, .authenticationRequired(endpoint: .devices)),
            (403, .accessDenied(endpoint: .devices)),
            (404, .notFound(endpoint: .devices)),
            (503, .unexpectedStatus(endpoint: .devices, statusCode: 503)),
        ]
        for (status, expected) in cases {
            let client = try makeClient(transport: RecordingTransport(response: .init(
                statusCode: status,
                body: Data("sensitive provider detail".utf8)
            )))
            await XCTAssertThrowsErrorAsync(try await client.devices(in: meshID())) { error in
                XCTAssertEqual(error as? MeshProviderError, expected)
            }
        }
    }

    func testRejectsOversizedAndMalformedResponses() async throws {
        let client = try makeClient(
            transport: RecordingTransport(response: .init(
                statusCode: 200,
                body: Data(repeating: 0x7B, count: 9)
            )),
            limits: try MeshResponseLimits(maximumResponseBytes: 8)
        )
        await XCTAssertThrowsErrorAsync(try await client.devices(in: meshID())) { error in
            XCTAssertEqual(
                error as? MeshProviderError,
                .responseTooLarge(endpoint: .devices, limit: 8, actual: 9)
            )
        }

        let malformed = try makeClient(transport: RecordingTransport(response: .init(
            statusCode: 200,
            body: Data("not-json".utf8)
        )))
        await XCTAssertThrowsErrorAsync(try await malformed.topology(for: meshID())) { error in
            XCTAssertEqual(error as? MeshProviderError, .decodingFailed(endpoint: .topology))
        }
    }

    func testRejectsCrossMeshDevicesAndTopology() async throws {
        var devices = try fixtureObject(named: "devices.synthetic")
        var data = try XCTUnwrap(devices["data"] as? [[String: Any]])
        data[0]["mesh_id"] = "00000000-0000-0000-0000-000000000999"
        devices["data"] = data
        let devicesClient = try makeClient(transport: RecordingTransport(response: .init(
            statusCode: 200,
            body: try JSONSerialization.data(withJSONObject: devices)
        )))
        await XCTAssertThrowsErrorAsync(try await devicesClient.devices(in: meshID())) { error in
            XCTAssertEqual(
                error as? MeshProviderError,
                .contractViolation(endpoint: .devices, violation: .meshIdentifierMismatch)
            )
        }

        var topology = try fixtureObject(named: "topology.synthetic")
        topology["mesh_id"] = "00000000-0000-0000-0000-000000000999"
        let topologyClient = try makeClient(transport: RecordingTransport(response: .init(
            statusCode: 200,
            body: try JSONSerialization.data(withJSONObject: topology)
        )))
        await XCTAssertThrowsErrorAsync(try await topologyClient.topology(for: meshID())) { error in
            XCTAssertEqual(
                error as? MeshProviderError,
                .contractViolation(endpoint: .topology, violation: .meshIdentifierMismatch)
            )
        }
    }

    func testRejectsEventCountMismatchAndUnknownTopologyNode() async throws {
        var events = try fixtureObject(named: "events.synthetic")
        events["count"] = 99
        let eventsClient = try makeClient(transport: RecordingTransport(response: .init(
            statusCode: 200,
            body: try JSONSerialization.data(withJSONObject: events)
        )))
        await XCTAssertThrowsErrorAsync(try await eventsClient.events(in: meshID())) { error in
            XCTAssertEqual(
                error as? MeshProviderError,
                .contractViolation(endpoint: .events, violation: .countMismatch)
            )
        }

        var topology = try fixtureObject(named: "topology.synthetic")
        var edges = try XCTUnwrap(topology["edges"] as? [[String: Any]])
        edges[0]["target"] = "00000000-0000-0000-0000-000000000999"
        topology["edges"] = edges
        let topologyClient = try makeClient(transport: RecordingTransport(response: .init(
            statusCode: 200,
            body: try JSONSerialization.data(withJSONObject: topology)
        )))
        await XCTAssertThrowsErrorAsync(try await topologyClient.topology(for: meshID())) { error in
            XCTAssertEqual(
                error as? MeshProviderError,
                .contractViolation(endpoint: .topology, violation: .edgeReferencesUnknownNode)
            )
        }
    }

    func testFreshnessHelpersHandleFreshStaleAndFutureDatedSnapshots() throws {
        let metadata = MeshSnapshotMetadata(
            meshID: try meshID(),
            fetchedAt: Date(timeIntervalSince1970: 100),
            source: .adminConsole,
            evidence: .currentSourceNotLiveVerified,
            networkBoundary: .privateNetwork
        )
        let policy = try MeshStalenessPolicy(maximumAge: 30, allowedFutureClockSkew: 5)

        XCTAssertEqual(metadata.age(at: Date(timeIntervalSince1970: 90)), 0)
        XCTAssertEqual(metadata.freshness(at: Date(timeIntervalSince1970: 120), policy: policy), .fresh)
        XCTAssertEqual(metadata.freshness(at: Date(timeIntervalSince1970: 131), policy: policy), .stale)
        XCTAssertEqual(metadata.freshness(at: Date(timeIntervalSince1970: 94), policy: policy), .futureDated)
    }

    func testNormalizesTransportFailureAndPreservesCancellation() async throws {
        let failed = try makeClient(transport: RecordingTransport(behavior: .failure))
        await XCTAssertThrowsErrorAsync(try await failed.devices(in: meshID())) { error in
            XCTAssertEqual(error as? MeshProviderError, .transportFailure(endpoint: .devices))
        }

        let cancelled = try makeClient(transport: RecordingTransport(behavior: .cancelled))
        await XCTAssertThrowsErrorAsync(try await cancelled.events(in: meshID())) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testRejectsInvalidLocalPolicies() {
        for value in [0, MeshResponseLimits.hardMaximumResponseBytes + 1] {
            XCTAssertThrowsError(try MeshResponseLimits(maximumResponseBytes: value)) { error in
                XCTAssertEqual(error as? MeshClientConfigurationError, .invalidMaximumResponseBytes)
            }
        }
        XCTAssertNoThrow(try MeshResponseLimits(
            maximumResponseBytes: MeshResponseLimits.hardMaximumResponseBytes
        ))
        for value in [-1.0, .infinity, .nan] {
            XCTAssertThrowsError(try MeshStalenessPolicy(maximumAge: value)) { error in
                XCTAssertEqual(error as? MeshStalenessPolicyError, .invalidDuration)
            }
        }
    }

    private func makeClient(
        transport: RecordingTransport,
        descriptor: ProviderDescriptor = MeshProvider.descriptor,
        limits: MeshResponseLimits = .standard
    ) throws -> MeshClient {
        let fixedNow = capturedAt
        return MeshClient(
            endpoint: try EndpointValidator.validate(
                "https://example.com",
                declaredBoundary: .hosted,
                hostedAccess: .granted
            ),
            transport: transport,
            credential: ProviderCredential(bytes: Data("opaque-test-credential".utf8)),
            descriptor: descriptor,
            limits: limits,
            now: { fixedNow }
        )
    }

    private func meshID() throws -> MeshID {
        try MeshID(validating: syntheticMeshValue)
    }

    private func fixtureData(named name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func fixtureObject(named name: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: fixtureData(named: name))
        return try XCTUnwrap(object as? [String: Any])
    }
}

private struct RecordedCall: Sendable {
    let request: ProviderRequest
    let hadCredential: Bool
}

private actor RecordingTransport: ProviderTransport {
    enum Behavior: Sendable {
        case response(ProviderResponse)
        case failure
        case cancelled
    }

    private let behavior: Behavior
    private var recordedCalls: [RecordedCall] = []

    init(response: ProviderResponse) {
        behavior = .response(response)
    }

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func send(
        _ request: ProviderRequest,
        to endpoint: ValidatedEndpoint,
        credential: ProviderCredential?
    ) throws -> ProviderResponse {
        recordedCalls.append(RecordedCall(request: request, hadCredential: credential != nil))
        switch behavior {
        case let .response(response):
            return response
        case .failure:
            throw StubTransportError.failed
        case .cancelled:
            throw CancellationError()
        }
    }

    func calls() -> [RecordedCall] {
        recordedCalls
    }

    func callCount() -> Int {
        recordedCalls.count
    }
}

private enum StubTransportError: Error {
    case failed
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (any Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

import Foundation
import XCTest
import WarRoomCore
@testable import WarRoomOpenWebUI

final class OpenWebUIClientTests: XCTestCase {
    func testEndpointPathsAndAdvertisedCapabilitiesMatchCapturedSlice() {
        XCTAssertEqual(OpenWebUIEndpoint.health.rawValue, "/health")
        XCTAssertEqual(OpenWebUIEndpoint.version.rawValue, "/api/version")
        XCTAssertEqual(OpenWebUIEndpoint.configuration.rawValue, "/api/config")
        XCTAssertEqual(OpenWebUIEndpoint.models.rawValue, "/api/models")
        XCTAssertEqual(OpenWebUIProvider.descriptor.capabilities, [.modelCatalog])
        XCTAssertFalse(OpenWebUIProvider.descriptor.supports(.chatCompletions))
        XCTAssertFalse(OpenWebUIProvider.descriptor.supports(.streamingChat))
        XCTAssertFalse(OpenWebUIProvider.descriptor.supports(.sourceCitations))
    }

    func testNativeChatCapabilityIsFailClosedUntilAuthenticatedContractIsCaptured() {
        let contract = OpenWebUIProvider.nativeChatContract

        XCTAssertFalse(contract.isAvailable)
        XCTAssertEqual(contract.blocker, .authenticatedCaptureRequired)
        XCTAssertEqual(
            contract.missingEvidence,
            Set(OpenWebUINativeChatEvidenceRequirement.allCases)
        )
        XCTAssertEqual(contract.advertisedCapabilities, [])
        XCTAssertFalse(OpenWebUIProvider.descriptor.supports(.chatCompletions))
        XCTAssertFalse(OpenWebUIProvider.descriptor.supports(.streamingChat))
        XCTAssertFalse(OpenWebUIProvider.descriptor.supports(.sourceCitations))
    }

    func testSanitizedChatBoundaryFixtureMatchesExecutableEvidenceGate() throws {
        let snapshot = try JSONDecoder().decode(
            NativeChatBoundarySnapshot.self,
            from: fixtureData(named: "native-chat-boundary.sanitized")
        )

        XCTAssertEqual(snapshot.fixtureKind, "sanitized_native_chat_contract_boundary")
        XCTAssertEqual(snapshot.origin, "https://webui.thox.ai")
        XCTAssertFalse(snapshot.retainedSensitiveValues)
        XCTAssertEqual(snapshot.contractState.blocker, OpenWebUIProvider.nativeChatContract.blocker)
        XCTAssertEqual(
            snapshot.contractState.missingEvidence.count,
            Set(snapshot.contractState.missingEvidence).count,
            "The capture checklist must not hide omissions behind duplicate entries"
        )
        XCTAssertEqual(
            Set(snapshot.contractState.missingEvidence),
            OpenWebUIProvider.nativeChatContract.missingEvidence
        )
        XCTAssertEqual(
            snapshot.observedRoutes,
            [
                .init(
                    method: "POST",
                    path: "/api/chat/completions",
                    status: 401,
                    contentType: "application/json",
                    bodyKeys: ["detail"]
                ),
                .init(
                    method: "GET",
                    path: "/api/v1/chats/",
                    status: 401,
                    contentType: "application/json",
                    bodyKeys: ["detail"]
                ),
            ]
        )
    }

    func testHealthUsesExactGetRequestAndAcceptsObservedResponse() async throws {
        let transport = RecordingTransport(response: .init(statusCode: 200, body: Data("OK".utf8)))
        let client = try makeClient(transport: transport)

        let health = try await client.health()

        XCTAssertEqual(health, OpenWebUIHealth(status: .ok))
        let calls = await transport.calls()
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.request.method, .get)
        XCTAssertEqual(call.request.relativePath, "/health")
        XCTAssertNil(call.request.body)
        XCTAssertEqual(call.endpoint, try endpoint())
        XCTAssertFalse(call.hadCredential)
    }

    func testVersionDecodesSanitizedObservedFixtureAndIgnoresUnknownMetadata() async throws {
        var object = try fixtureObject(named: "api-version.sanitized")
        object["deployment_id"] = "discarded-by-decoder"
        let body = try JSONSerialization.data(withJSONObject: object)
        let client = try makeClient(transport: RecordingTransport(response: .init(statusCode: 200, body: body)))

        let version = try await client.version()
        XCTAssertEqual(version, OpenWebUIVersion(version: "0.11.0"))
    }

    func testPublicDiscoveryDoesNotForwardCredential() async throws {
        let body = try fixtureData(named: "api-version.sanitized")
        let transport = RecordingTransport(response: .init(statusCode: 200, body: body))
        let client = try makeClient(
            transport: transport,
            credential: ProviderCredential(bytes: Data("must-not-be-forwarded".utf8))
        )

        _ = try await client.version()

        let calls = await transport.calls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertFalse(try XCTUnwrap(calls.first).hadCredential)
    }

    func testConfigurationDecodesSanitizedObservedFixture() async throws {
        let body = try fixtureData(named: "api-config.sanitized")
        let client = try makeClient(transport: RecordingTransport(response: .init(statusCode: 200, body: body)))

        let configuration = try await client.configuration()

        XCTAssertTrue(configuration.status)
        XCTAssertEqual(configuration.name, "THOX (Open WebUI)")
        XCTAssertEqual(configuration.version, "0.11.0")
        XCTAssertTrue(configuration.features.auth)
        XCTAssertTrue(configuration.features.enableLoginForm)
        XCTAssertTrue(configuration.features.enableWebSocket)
        XCTAssertFalse(configuration.features.enableSignup)
    }

    func testModelsDecodeProvisionalSyntheticEnvelopeAndForwardOpaqueCredential() async throws {
        let body = try fixtureData(named: "models.synthetic-unverified")
        let transport = RecordingTransport(response: .init(statusCode: 200, body: body))
        let credential = ProviderCredential(bytes: Data("not-recorded".utf8))
        let client = try makeClient(transport: transport, credential: credential)

        let catalog = try await client.models()

        XCTAssertEqual(catalog.data, [OpenWebUIModel(id: "local-test-model", name: "Local Test Model")])
        let calls = await transport.calls()
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.request.relativePath, "/api/models")
        XCTAssertTrue(call.hadCredential)
    }

    func testCapabilityGatePreventsModelTransportCall() async throws {
        let transport = RecordingTransport(response: .init(statusCode: 200, body: Data()))
        let descriptor = ProviderDescriptor(
            id: ProviderID(rawValue: "disabled-open-webui"),
            displayName: "Disabled Open WebUI",
            capabilities: []
        )
        let client = try makeClient(transport: transport, descriptor: descriptor)

        await XCTAssertThrowsErrorAsync(try await client.models()) { error in
            XCTAssertEqual(error as? OpenWebUIProviderError, .unsupportedCapability(.modelCatalog))
        }
        let calls = await transport.calls()
        XCTAssertEqual(calls.count, 0)
    }

    func testMapsAuthenticationAndAuthorizationStatusesWithoutDecodingBodies() async throws {
        for (status, expected) in [
            (401, OpenWebUIProviderError.authenticationRequired(endpoint: .models)),
            (403, OpenWebUIProviderError.accessDenied(endpoint: .models)),
        ] {
            let client = try makeClient(
                transport: RecordingTransport(
                    response: .init(statusCode: status, body: Data("sensitive error detail".utf8))
                )
            )
            await XCTAssertThrowsErrorAsync(try await client.models()) { error in
                XCTAssertEqual(error as? OpenWebUIProviderError, expected)
            }
        }
    }

    func testRejectsUnexpectedStatusWithTypedNonSensitiveError() async throws {
        let client = try makeClient(
            transport: RecordingTransport(response: .init(statusCode: 503, body: Data()))
        )

        await XCTAssertThrowsErrorAsync(try await client.health()) { error in
            XCTAssertEqual(
                error as? OpenWebUIProviderError,
                .unexpectedStatus(endpoint: .health, statusCode: 503)
            )
        }
    }

    func testRejectsOversizedResponseBeforeDecoding() async throws {
        let limits = try OpenWebUIResponseLimits(maximumResponseBytes: 8)
        let body = Data(repeating: 0x7B, count: 9)
        let client = try makeClient(
            transport: RecordingTransport(response: .init(statusCode: 200, body: body)),
            limits: limits
        )

        await XCTAssertThrowsErrorAsync(try await client.version()) { error in
            XCTAssertEqual(
                error as? OpenWebUIProviderError,
                .responseTooLarge(endpoint: .version, limit: 8, actual: 9)
            )
        }
    }

    func testMapsMalformedJSONAndInvalidPayloadSeparately() async throws {
        let malformed = try makeClient(
            transport: RecordingTransport(
                response: .init(statusCode: 200, body: Data("not-json".utf8))
            )
        )
        await XCTAssertThrowsErrorAsync(try await malformed.version()) { error in
            XCTAssertEqual(error as? OpenWebUIProviderError, .decodingFailed(endpoint: .version))
        }

        let emptyVersion = Data(#"{"version":"   "}"#.utf8)
        let invalid = try makeClient(
            transport: RecordingTransport(response: .init(statusCode: 200, body: emptyVersion))
        )
        await XCTAssertThrowsErrorAsync(try await invalid.version()) { error in
            XCTAssertEqual(error as? OpenWebUIProviderError, .invalidPayload(endpoint: .version))
        }
    }

    func testRejectsInvalidHealthTextAndUnknownHealthState() async throws {
        let invalidText = try makeClient(
            transport: RecordingTransport(response: .init(statusCode: 200, body: Data([0xFF])))
        )
        await XCTAssertThrowsErrorAsync(try await invalidText.health()) { error in
            XCTAssertEqual(error as? OpenWebUIProviderError, .invalidText(endpoint: .health))
        }

        let unknown = try makeClient(
            transport: RecordingTransport(response: .init(statusCode: 200, body: Data("DEGRADED".utf8)))
        )
        await XCTAssertThrowsErrorAsync(try await unknown.health()) { error in
            XCTAssertEqual(error as? OpenWebUIProviderError, .invalidHealthResponse)
        }
    }

    func testNormalizesTransportFailureAndPreservesCancellation() async throws {
        let failed = try makeClient(transport: RecordingTransport(behavior: .failure))
        await XCTAssertThrowsErrorAsync(try await failed.configuration()) { error in
            XCTAssertEqual(error as? OpenWebUIProviderError, .transportFailure(endpoint: .configuration))
        }

        let cancelled = try makeClient(transport: RecordingTransport(behavior: .cancelled))
        await XCTAssertThrowsErrorAsync(try await cancelled.health()) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testRejectsInvalidResponseLimit() {
        XCTAssertThrowsError(try OpenWebUIResponseLimits(maximumResponseBytes: 0)) { error in
            XCTAssertEqual(
                error as? OpenWebUIClientConfigurationError,
                .invalidMaximumResponseBytes
            )
        }
    }

    private func makeClient(
        transport: RecordingTransport,
        credential: ProviderCredential? = nil,
        descriptor: ProviderDescriptor = OpenWebUIProvider.descriptor,
        limits: OpenWebUIResponseLimits = .standard
    ) throws -> OpenWebUIClient {
        OpenWebUIClient(
            endpoint: try endpoint(),
            transport: transport,
            credential: credential,
            descriptor: descriptor,
            limits: limits
        )
    }

    private func endpoint() throws -> ValidatedEndpoint {
        try EndpointValidator.validate(
            "https://example.com",
            declaredBoundary: .hosted,
            hostedAccess: .granted
        )
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

private struct NativeChatBoundarySnapshot: Decodable {
    struct ContractState: Decodable {
        let blocker: OpenWebUINativeChatContract.Blocker
        let missingEvidence: [OpenWebUINativeChatEvidenceRequirement]

        private enum CodingKeys: String, CodingKey {
            case blocker
            case missingEvidence = "missing_evidence"
        }
    }

    struct ObservedRoute: Decodable, Equatable {
        let method: String
        let path: String
        let status: Int
        let contentType: String
        let bodyKeys: [String]

        private enum CodingKeys: String, CodingKey {
            case method, path, status
            case contentType = "content_type"
            case bodyKeys = "body_keys"
        }
    }

    let fixtureKind: String
    let origin: String
    let observedRoutes: [ObservedRoute]
    let contractState: ContractState
    let retainedSensitiveValues: Bool

    private enum CodingKeys: String, CodingKey {
        case fixtureKind = "fixture_kind"
        case origin
        case observedRoutes = "observed_routes"
        case contractState = "contract_state"
        case retainedSensitiveValues = "retained_sensitive_values"
    }
}

private struct RecordedCall: Sendable {
    let request: ProviderRequest
    let endpoint: ValidatedEndpoint
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
        recordedCalls.append(
            RecordedCall(
                request: request,
                endpoint: endpoint,
                hadCredential: credential != nil
            )
        )
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

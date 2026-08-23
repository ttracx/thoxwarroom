import Foundation
import XCTest
import WarRoomCore
@testable import WarRoomHermes

final class HermesAPIClientTests: XCTestCase {
    func testCapabilitiesUsesTypedContract() async throws {
        let transport = TransportStub(responses: [
            ProviderResponse(statusCode: 200, body: try fixtureData("capabilities"))
        ])
        let client = try makeClient(transport: transport)

        let response = try await client.capabilities()

        XCTAssertEqual(response.runtimeMode, "server_agent")
        XCTAssertEqual(response.features["runs"], true)
        XCTAssertEqual(response.endpoints["runs"], "/v1/runs")
        let requests = await transport.capturedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.relativePath, "/v1/capabilities")
        XCTAssertNil(request.body)
    }

    func testSubmitAcceptsOpaqueRunIDAndEncodesDocumentedFields() async throws {
        let transport = TransportStub(responses: [
            ProviderResponse(statusCode: 202, body: try fixtureData("run-started"))
        ])
        let client = try makeClient(transport: transport)
        let request = HermesRunSubmitRequest(
            input: .text("summarize locally"),
            instructions: "cite sources",
            model: "local-model"
        )

        let response = try await client.submit(request)

        XCTAssertEqual(response.runID.rawValue, "opaque-A7_42")
        XCTAssertEqual(response.status, .started)
        let requests = await transport.capturedRequests()
        let sent = try XCTUnwrap(requests.first)
        XCTAssertEqual(sent.method, .post)
        XCTAssertEqual(sent.relativePath, "/v1/runs")
        let body = try XCTUnwrap(sent.body)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("run_"))
        XCTAssertEqual(try JSONDecoder().decode(HermesRunSubmitRequest.self, from: body), request)
    }

    func testStatusDoesNotRequireRunPrefix() async throws {
        let transport = TransportStub(responses: [
            ProviderResponse(statusCode: 200, body: try fixtureData("run-status"))
        ])
        let client = try makeClient(transport: transport)
        let runID = try XCTUnwrap(HermesRunID(rawValue: "opaque-A7_42"))

        let response = try await client.status(runID: runID)

        XCTAssertEqual(response.status, .running)
        let requests = await transport.capturedRequests()
        XCTAssertEqual(try XCTUnwrap(requests.first).relativePath, "/v1/runs/opaque-A7_42")
    }

    func testApprovalSendsCanonicalChoiceAndDecodesSuccess() async throws {
        let transport = TransportStub(responses: [
            ProviderResponse(statusCode: 200, body: try fixtureData("approval-success"))
        ])
        let client = try makeClient(transport: transport)
        let runID = try XCTUnwrap(HermesRunID(rawValue: "opaque-A7_42"))

        let response = try await client.approve(
            runID: runID,
            request: HermesApprovalRequest(choice: .once)
        )

        XCTAssertEqual(response.choice, .once)
        XCTAssertEqual(response.resolved, 1)
        let requests = await transport.capturedRequests()
        let sent = try XCTUnwrap(requests.first)
        XCTAssertEqual(sent.relativePath, "/v1/runs/opaque-A7_42/approval")
        let encoded = String(decoding: try XCTUnwrap(sent.body), as: UTF8.self)
        XCTAssertTrue(encoded.contains("\"choice\":\"once\""))
        XCTAssertFalse(encoded.contains("approve"))
    }

    func testApproval409IsExplicitConflict() async throws {
        let transport = TransportStub(responses: [ProviderResponse(statusCode: 409, body: Data())])
        let client = try makeClient(transport: transport)
        let runID = try XCTUnwrap(HermesRunID(rawValue: "opaque-A7_42"))

        do {
            _ = try await client.approve(
                runID: runID,
                request: HermesApprovalRequest(choice: .deny)
            )
            XCTFail("Expected conflict")
        } catch {
            XCTAssertEqual(error as? HermesClientError, .approvalUnavailable)
        }
    }

    func testStopSendsNoInventedBody() async throws {
        let transport = TransportStub(responses: [
            ProviderResponse(statusCode: 202, body: try fixtureData("stop-success"))
        ])
        let client = try makeClient(transport: transport)
        let runID = try XCTUnwrap(HermesRunID(rawValue: "opaque-A7_42"))

        let response = try await client.stop(runID: runID)

        XCTAssertEqual(response.status, .cancelled)
        let requests = await transport.capturedRequests()
        let sent = try XCTUnwrap(requests.first)
        XCTAssertEqual(sent.relativePath, "/v1/runs/opaque-A7_42/stop")
        XCTAssertNil(sent.body)
    }

    func testRequestAndResponseBoundsAreEnforced() async throws {
        let transport = TransportStub(responses: [
            ProviderResponse(statusCode: 200, body: Data(repeating: 65, count: 33))
        ])
        let client = try makeClient(
            transport: transport,
            limits: try HermesClientLimits(
                maximumRequestBodyBytes: 32,
                maximumResponseBodyBytes: 32,
                maximumSSEEventBytes: 16
            )
        )

        do {
            _ = try await client.submit(HermesRunSubmitRequest(input: .text(String(repeating: "x", count: 64))))
            XCTFail("Expected request limit")
        } catch {
            XCTAssertEqual(error as? HermesClientError, .requestTooLarge)
        }
        let requestsAfterRejectedBody = await transport.capturedRequests()
        XCTAssertTrue(requestsAfterRejectedBody.isEmpty)

        do {
            _ = try await client.capabilities()
            XCTFail("Expected response limit")
        } catch {
            XCTAssertEqual(error as? HermesClientError, .responseTooLarge)
        }
    }

    func testTransportCancellationPropagates() async throws {
        let transport = TransportStub(responses: [], cancellationOnSend: true)
        let client = try makeClient(transport: transport)

        do {
            _ = try await client.capabilities()
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: cancellation is not translated to a user-facing client error.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsInvalidClientLimits() {
        XCTAssertThrowsError(
            try HermesClientLimits(
                maximumRequestBodyBytes: 0,
                maximumResponseBodyBytes: 32,
                maximumSSEEventBytes: 16
            )
        ) {
            XCTAssertEqual($0 as? HermesLimitError, .invalidClientLimits)
        }
        XCTAssertThrowsError(
            try HermesClientLimits(
                maximumRequestBodyBytes: 32,
                maximumResponseBodyBytes: Int.max,
                maximumSSEEventBytes: Int.max
            )
        ) {
            XCTAssertEqual($0 as? HermesLimitError, .invalidClientLimits)
        }
    }

    func testEventsUseBoundedSSEParserThroughTransport() async throws {
        let eventsURL = try XCTUnwrap(
            Bundle.module.url(forResource: "events-fragmented", withExtension: "sse")
        )
        let transport = TransportStub(responses: [
            ProviderResponse(statusCode: 200, body: try Data(contentsOf: eventsURL))
        ])
        let client = try makeClient(transport: transport)
        let runID = try XCTUnwrap(HermesRunID(rawValue: "opaque-A7_42"))

        let events = try await client.events(runID: runID)

        XCTAssertEqual(events.count, 4)
        let requests = await transport.capturedRequests()
        XCTAssertEqual(try XCTUnwrap(requests.first).relativePath, "/v1/runs/opaque-A7_42/events")
    }

    func testUnsafeOpaqueRunRouteIsRejectedBeforeTransport() async throws {
        let transport = TransportStub(responses: [])
        let client = try makeClient(transport: transport)
        let runID = try XCTUnwrap(HermesRunID(rawValue: "opaque/other"))

        do {
            _ = try await client.status(runID: runID)
            XCTFail("Expected route rejection")
        } catch {
            XCTAssertEqual(error as? HermesClientError, .invalidRunRoute)
        }
        let requests = await transport.capturedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    private func makeClient(
        transport: TransportStub,
        limits: HermesClientLimits = .default
    ) throws -> HermesAPIClient {
        let endpoint = try EndpointValidator.validate(
            "http://127.0.0.1",
            declaredBoundary: .localMachine
        )
        return HermesAPIClient(transport: transport, endpoint: endpoint, limits: limits)
    }

    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
}

private actor TransportStub: ProviderTransport {
    private var responses: [ProviderResponse]
    private let cancellationOnSend: Bool
    private(set) var requests: [ProviderRequest] = []

    init(responses: [ProviderResponse], cancellationOnSend: Bool = false) {
        self.responses = responses
        self.cancellationOnSend = cancellationOnSend
    }

    func send(
        _ request: ProviderRequest,
        to endpoint: ValidatedEndpoint,
        credential: ProviderCredential?
    ) async throws -> ProviderResponse {
        requests.append(request)
        if cancellationOnSend { throw CancellationError() }
        guard !responses.isEmpty else { throw TransportStubError.noResponse }
        return responses.removeFirst()
    }

    func capturedRequests() -> [ProviderRequest] {
        requests
    }
}

private enum TransportStubError: Error {
    case noResponse
}

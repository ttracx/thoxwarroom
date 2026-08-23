import XCTest
import WarRoomCore
@testable import WarRoomHermes

final class HermesEventStreamingClientTests: XCTestCase {
    func testStreamsFragmentedEventsWithCredentialAndExactRoute() async throws {
        let runID = try XCTUnwrap(HermesRunID(rawValue: "opaque-A7_42"))
        let transport = StreamingTransportStub(
            statusCode: 200,
            chunks: [
                Data("data: {\"event\":\"message.delta\",\"run_id\":\"opaque-A7_42\",\"delta\":\"hel".utf8),
                Data("lo\"}\n\ndata: {\"event\":\"run.completed\",\"run_id\":\"opaque-A7_42\"}\n\n".utf8),
            ]
        )
        let client = try makeClient(
            transport: transport,
            credential: ProviderCredential(bytes: Data("credential".utf8))
        )

        let stream = try await client.events(runID: runID)
        var received: [HermesRunEvent] = []
        for try await event in stream { received.append(event) }

        XCTAssertEqual(received.count, 2)
        guard case .messageDelta(let delta) = received[0] else {
            return XCTFail("Expected message delta")
        }
        XCTAssertEqual(delta.delta, "hello")
        guard case .runCompleted(let metadata) = received[1] else {
            return XCTFail("Expected completion")
        }
        XCTAssertEqual(metadata.runID, runID)
        let capture = await transport.capture
        XCTAssertEqual(capture?.request.method, .get)
        XCTAssertEqual(capture?.request.relativePath, "/v1/runs/opaque-A7_42/events")
        XCTAssertTrue(capture?.credentialWasPresent == true)
    }

    func testRejectsUnexpectedStatusBeforeReturningEventStream() async throws {
        let transport = StreamingTransportStub(statusCode: 401, chunks: [])
        let client = try makeClient(transport: transport)
        let runID = try XCTUnwrap(HermesRunID(rawValue: "opaque-A7_42"))

        do {
            _ = try await client.events(runID: runID)
            XCTFail("Expected status rejection")
        } catch {
            XCTAssertEqual(error as? HermesClientError, .unexpectedStatus(401))
        }
    }

    func testCrossRunEventTerminatesStreamFailClosed() async throws {
        let transport = StreamingTransportStub(
            statusCode: 200,
            chunks: [Data("data: {\"event\":\"run.completed\",\"run_id\":\"other-run\"}\n\n".utf8)]
        )
        let client = try makeClient(transport: transport)
        let runID = try XCTUnwrap(HermesRunID(rawValue: "opaque-A7_42"))
        let stream = try await client.events(runID: runID)

        do {
            for try await _ in stream {}
            XCTFail("Expected workspace/run isolation failure")
        } catch {
            XCTAssertEqual(error as? HermesClientError, .invalidResponse)
        }
    }

    func testOversizedIncrementTerminatesWithoutYieldingPartialEvent() async throws {
        let limits = try HermesClientLimits(
            maximumRequestBodyBytes: 128,
            maximumResponseBodyBytes: 32,
            maximumSSEEventBytes: 16
        )
        let transport = StreamingTransportStub(
            statusCode: 200,
            chunks: [Data(repeating: 0x61, count: 33)]
        )
        let client = try makeClient(transport: transport, limits: limits)
        let runID = try XCTUnwrap(HermesRunID(rawValue: "opaque-A7_42"))
        let stream = try await client.events(runID: runID)

        do {
            for try await _ in stream {}
            XCTFail("Expected bounded-buffer failure")
        } catch {
            XCTAssertEqual(error as? HermesSSEError, .bufferLimitExceeded)
        }
    }

    func testConsumerCancellationCancelsStreamingProducer() async throws {
        let termination = StreamingTerminationProbe()
        let transport = NeverEndingStreamingTransport(termination: termination)
        let client = try makeClient(transport: transport)
        let runID = try XCTUnwrap(HermesRunID(rawValue: "opaque-A7_42"))
        let stream = try await client.events(runID: runID)

        let task = Task {
            for try await _ in stream {}
        }
        task.cancel()
        _ = await task.result

        let cancelled = await termination.waitForCancellation()
        XCTAssertTrue(cancelled)
    }

    private func makeClient(
        transport: any HermesEventStreamingTransport,
        credential: ProviderCredential? = nil,
        limits: HermesClientLimits = .default
    ) throws -> HermesEventStreamingClient {
        let endpoint = try EndpointValidator.validate(
            "http://127.0.0.1:8642",
            declaredBoundary: .localMachine,
            policy: EndpointValidationPolicy(allowedHTTPPorts: [80, 8_642])
        )
        return HermesEventStreamingClient(
            transport: transport,
            endpoint: endpoint,
            credential: credential,
            limits: limits
        )
    }
}

private actor StreamingTransportStub: HermesEventStreamingTransport {
    struct Capture: Sendable {
        let request: ProviderRequest
        let credentialWasPresent: Bool
    }

    private let statusCode: Int
    private let chunks: [Data]
    private(set) var capture: Capture?

    init(statusCode: Int, chunks: [Data]) {
        self.statusCode = statusCode
        self.chunks = chunks
    }

    func stream(
        _ request: ProviderRequest,
        to endpoint: ValidatedEndpoint,
        credential: ProviderCredential?
    ) -> HermesProviderByteStream {
        capture = Capture(request: request, credentialWasPresent: credential != nil)
        let chunks = self.chunks
        return HermesProviderByteStream(
            statusCode: statusCode,
            bytes: AsyncThrowingStream { continuation in
                for chunk in chunks { continuation.yield(chunk) }
                continuation.finish()
            }
        )
    }
}

private actor StreamingTerminationProbe {
    private var cancelled = false

    func markCancelled() { cancelled = true }

    func waitForCancellation() async -> Bool {
        for _ in 0..<100 where !cancelled {
            await Task.yield()
        }
        return cancelled
    }
}

private struct NeverEndingStreamingTransport: HermesEventStreamingTransport {
    let termination: StreamingTerminationProbe

    func stream(
        _ request: ProviderRequest,
        to endpoint: ValidatedEndpoint,
        credential: ProviderCredential?
    ) -> HermesProviderByteStream {
        HermesProviderByteStream(
            statusCode: 200,
            bytes: AsyncThrowingStream { continuation in
                continuation.onTermination = { @Sendable _ in
                    Task { await termination.markCancelled() }
                }
            }
        )
    }
}

import Foundation
import XCTest
@testable import WarRoomAppleInfrastructure
import WarRoomCore

final class DNSBoundHermesEventStreamingTransportTests: XCTestCase {
    func testStreamsChunkedSSEAfterResolutionAndInjectsCredentialAtSendTime() async throws {
        let resolver = SequencedHermesResolver(["10.1.2.3"])
        let connection = ScriptedHermesConnection([
            receive(
                "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Type: text/event-stream\r\n\r\n"
                    + "5\r\ndata:\r\n5\r\n ok\n\n\r\n0\r\n\r\n",
                complete: true
            ),
        ])
        let factory = ScriptedHermesConnectionFactory([connection])
        let transport = try makeTransport(resolver: resolver, factory: factory)

        let response = try await transport.stream(
            try ProviderRequest(method: .get, relativePath: "/events"),
            to: try privateEndpoint(),
            credential: ProviderCredential(bytes: Data("fixture-value".utf8))
        )

        XCTAssertEqual(response.statusCode, 200)
        let body = try await collect(response.bytes)
        let hostnames = await resolver.hostnames
        XCTAssertEqual(body, Data("data: ok\n\n".utf8))
        XCTAssertEqual(hostnames, ["provider.internal"])
        XCTAssertEqual(factory.createdAddresses, ["10.1.2.3"])
        let request = try XCTUnwrap(connection.sentRequests.first)
        XCTAssertTrue(request.starts(with: Data("GET /api/events HTTP/1.1\r\n".utf8)))
        XCTAssertTrue(request.contains(Data("Host: provider.internal\r\n".utf8)))
        XCTAssertTrue(request.contains(Data("Accept: text/event-stream\r\n".utf8)))
        XCTAssertTrue(request.contains(Data("Authorization: Bearer fixture-value\r\n".utf8)))
        XCTAssertEqual(connection.cancelCount, 1)
    }

    func testParsesFixedLengthAndEOFFramedBodiesIncrementally() async throws {
        let fixed = ScriptedHermesConnection([
            receive("HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nAB", complete: false),
            receive("CD", complete: false),
        ])
        let eof = ScriptedHermesConnection([
            receive("HTTP/1.1 200 OK\r\n\r\nEF", complete: false),
            receive("GH", complete: true),
        ])
        let resolver = SequencedHermesResolver(["10.1.2.3"], ["10.1.2.4"])
        let transport = try makeTransport(
            resolver: resolver,
            factory: ScriptedHermesConnectionFactory([fixed, eof])
        )
        let endpoint = try privateEndpoint()
        let request = try ProviderRequest(method: .get, relativePath: "/events")

        let fixedResponse = try await transport.stream(request, to: endpoint, credential: nil)
        let fixedBody = try await collect(fixedResponse.bytes)
        XCTAssertEqual(fixedBody, Data("ABCD".utf8))
        let eofResponse = try await transport.stream(request, to: endpoint, credential: nil)
        let eofBody = try await collect(eofResponse.bytes)
        XCTAssertEqual(eofBody, Data("EFGH".utf8))
    }

    func testExactOriginRedirectReResolvesAndCancelsEachConnectionOnce() async throws {
        let first = ScriptedHermesConnection([
            receive(
                "HTTP/1.1 307 Temporary Redirect\r\nLocation: /api/next\r\nContent-Length: 0\r\n\r\n",
                complete: false
            ),
        ])
        let second = ScriptedHermesConnection([
            receive("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK", complete: false),
        ])
        let resolver = SequencedHermesResolver(["10.1.2.3"], ["10.1.2.4"])
        let factory = ScriptedHermesConnectionFactory([first, second])
        let transport = try makeTransport(resolver: resolver, factory: factory)

        let response = try await transport.stream(
            try ProviderRequest(method: .get, relativePath: "/events"),
            to: try privateEndpoint(),
            credential: nil
        )

        let body = try await collect(response.bytes)
        let hostnames = await resolver.hostnames
        XCTAssertEqual(body, Data("OK".utf8))
        XCTAssertEqual(hostnames, ["provider.internal", "provider.internal"])
        XCTAssertEqual(factory.createdAddresses, ["10.1.2.3", "10.1.2.4"])
        XCTAssertEqual(first.cancelCount, 1)
        XCTAssertEqual(second.cancelCount, 1)
        XCTAssertTrue(try XCTUnwrap(second.sentRequests.first).starts(with: Data("GET /api/next HTTP/1.1\r\n".utf8)))
    }

    func testRejectsSchemeHostAndEffectivePortRedirectChanges() async throws {
        let locations = [
            "http://provider.internal/api/next",
            "https://other.internal/api/next",
            "https://provider.internal:444/api/next",
        ]
        for location in locations {
            let connection = ScriptedHermesConnection([
                receive(
                    "HTTP/1.1 302 Found\r\nLocation: \(location)\r\nContent-Length: 0\r\n\r\n",
                    complete: false
                ),
            ])
            let factory = ScriptedHermesConnectionFactory([connection])
            let transport = try makeTransport(
                resolver: SequencedHermesResolver(["10.1.2.3"]),
                factory: factory
            )
            await assertStreamOpenFailure(transport, equals: .protocolFailure(.unknown))
            XCTAssertEqual(factory.makeCount, 1)
            XCTAssertEqual(connection.cancelCount, 1)
        }
    }

    func testRedirectLimitFailsBeforeAnotherResolutionOrConnection() async throws {
        let connection = ScriptedHermesConnection([
            receive(
                "HTTP/1.1 307 Temporary Redirect\r\nLocation: /api/next\r\nContent-Length: 0\r\n\r\n",
                complete: false
            ),
        ])
        let resolver = SequencedHermesResolver(["10.1.2.3"])
        let factory = ScriptedHermesConnectionFactory([connection])
        let transport = try makeTransport(
            resolver: resolver,
            factory: factory,
            maximumRedirects: 0
        )

        await assertStreamOpenFailure(transport, equals: .protocolFailure(.unknown))
        let resolutionCount = await resolver.hostnames.count
        XCTAssertEqual(resolutionCount, 1)
        XCTAssertEqual(factory.makeCount, 1)
        XCTAssertEqual(connection.cancelCount, 1)
    }

    func testBoundaryFailureAndInvalidCredentialNeverCreateConnection() async throws {
        let boundaryFactory = ScriptedHermesConnectionFactory([])
        let boundaryTransport = try makeTransport(
            resolver: SequencedHermesResolver(["8.8.8.8"]),
            factory: boundaryFactory
        )
        await assertStreamOpenFailure(boundaryTransport, equals: .protocolFailure(.unknown))
        XCTAssertEqual(boundaryFactory.makeCount, 0)

        let credentialResolver = SequencedHermesResolver(["10.1.2.3"])
        let credentialFactory = ScriptedHermesConnectionFactory([])
        let credentialTransport = try makeTransport(
            resolver: credentialResolver,
            factory: credentialFactory
        )
        do {
            _ = try await credentialTransport.stream(
                try ProviderRequest(method: .get, relativePath: "/events"),
                to: try privateEndpoint(),
                credential: ProviderCredential(bytes: Data([0x0A]))
            )
            XCTFail("Expected invalid credential")
        } catch {
            XCTAssertEqual(error as? NetworkTerminalError, .protocolFailure(.unknown))
        }
        let credentialHostnames = await credentialResolver.hostnames
        XCTAssertEqual(credentialHostnames, ["provider.internal"])
        XCTAssertEqual(credentialFactory.makeCount, 0)
    }

    func testFiniteConsumerBufferOverflowFailsClosedAndCancelsOnce() async throws {
        let policy = try HermesEventStreamingTransportPolicy(
            maximumBufferedChunks: 1,
            maximumChunkBytes: 4,
            requestTimeout: 2,
            resourceTimeout: 4
        )
        let limits = try BoundedHTTP1Limits(
            maximumHeaderBytes: 1_024,
            maximumHeaderCount: 16,
            maximumLineBytes: 512,
            maximumBodyBytes: 32,
            maximumDeliveryBytes: 1
        )
        let connection = ScriptedHermesConnection([
            receive("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nABC", complete: false),
        ])
        let transport = try DNSBoundHermesEventStreamingTransport(
            policy: policy,
            httpLimits: limits,
            resolver: SequencedHermesResolver(["10.1.2.3"]),
            connectionFactory: ScriptedHermesConnectionFactory([connection])
        )

        let response = try await transport.stream(
            try ProviderRequest(method: .get, relativePath: "/events"),
            to: try privateEndpoint(),
            credential: nil
        )
        // Hold the consumer until the scripted producer reaches its terminal
        // transition; otherwise executor scheduling can drain the one-element
        // buffer between yields and make this overflow test nondeterministic.
        await connection.waitUntilCancelled()
        var iterator = response.bytes.makeAsyncIterator()
        let first = try await iterator.next()
        XCTAssertEqual(first, Data("A".utf8))
        do {
            _ = try await iterator.next()
            XCTFail("Expected finite-buffer failure")
        } catch {
            XCTAssertEqual(error as? NetworkTerminalError, .streamBufferExceeded(limit: 1))
        }
        XCTAssertEqual(connection.cancelCount, 1)
    }

    func testResponseTimeoutCancelsHangingConnectionOnce() async throws {
        let policy = try HermesEventStreamingTransportPolicy(
            maximumBufferedChunks: 2,
            maximumChunkBytes: 64,
            requestTimeout: 0.02,
            resourceTimeout: 1
        )
        let connection = ScriptedHermesConnection([])
        let transport = try DNSBoundHermesEventStreamingTransport(
            policy: policy,
            resolver: SequencedHermesResolver(["10.1.2.3"]),
            connectionFactory: ScriptedHermesConnectionFactory([connection])
        )

        await assertStreamOpenFailure(transport, equals: .timedOut)
        XCTAssertEqual(connection.cancelCount, 1)
    }

    func testActivityTimeoutStillAppliesAfterResponseHead() async throws {
        let policy = try HermesEventStreamingTransportPolicy(
            maximumBufferedChunks: 2,
            maximumChunkBytes: 128,
            requestTimeout: 0.02,
            resourceTimeout: 1
        )
        let connection = ScriptedHermesConnection([
            receive("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n", complete: false),
        ])
        let transport = try DNSBoundHermesEventStreamingTransport(
            policy: policy,
            resolver: SequencedHermesResolver(["10.1.2.3"]),
            connectionFactory: ScriptedHermesConnectionFactory([connection])
        )

        let response = try await transport.stream(
            try ProviderRequest(method: .get, relativePath: "/events"),
            to: try privateEndpoint(),
            credential: nil
        )
        var iterator = response.bytes.makeAsyncIterator()
        do {
            _ = try await iterator.next()
            XCTFail("Expected post-head activity timeout")
        } catch {
            XCTAssertEqual(error as? NetworkTerminalError, .timedOut)
        }
        XCTAssertEqual(connection.cancelCount, 1)
    }

    func testCallerCancellationBeforeResponseCancelsConnectionOnce() async throws {
        let connection = ScriptedHermesConnection([])
        let factory = ScriptedHermesConnectionFactory([connection])
        let transport = try makeTransport(
            resolver: SequencedHermesResolver(["10.1.2.3"]),
            factory: factory
        )
        let task = Task {
            try await transport.stream(
                try ProviderRequest(method: .get, relativePath: "/events"),
                to: try privateEndpoint(),
                credential: nil
            )
        }
        for _ in 0..<100 {
            if factory.makeCount == 1 { break }
            try await Task.sleep(for: .milliseconds(1))
        }

        task.cancel()
        switch await task.result {
        case .success:
            XCTFail("Expected cancellation")
        case let .failure(error):
            XCTAssertEqual(error as? NetworkTerminalError, .cancelled)
        }
        XCTAssertEqual(factory.makeCount, 1)
        XCTAssertEqual(connection.cancelCount, 1)
    }

    func testRejectsNonGETAndErrorsRemainRedacted() async throws {
        let transport = try makeTransport(
            resolver: SequencedHermesResolver(["10.1.2.3"]),
            factory: ScriptedHermesConnectionFactory([])
        )
        do {
            _ = try await transport.stream(
                try ProviderRequest(method: .post, relativePath: "/events", body: Data()),
                to: try privateEndpoint(),
                credential: nil
            )
            XCTFail("Expected GET-only rejection")
        } catch {
            XCTAssertEqual(
                error as? DNSBoundHermesEventStreamingTransportError,
                .unsupportedRequest
            )
        }

        let errors: [DNSBoundHermesEventStreamingTransportError] = [
            .unsupportedRequest,
            .invalidRelativePath,
            .invalidCredential,
            .invalidRedirect,
            .redirectLimitExceeded(limit: 3),
            .noApprovedPeer,
            .invalidReceiveLimit,
        ]
        for error in errors {
            XCTAssertFalse(error.localizedDescription.contains("provider.internal"))
            XCTAssertFalse(error.localizedDescription.contains("10.1.2.3"))
            XCTAssertFalse(error.localizedDescription.contains("Authorization"))
            XCTAssertFalse(error.localizedDescription.contains("fixture-value"))
        }
    }

    private func makeTransport(
        resolver: SequencedHermesResolver,
        factory: ScriptedHermesConnectionFactory,
        maximumRedirects: Int = 3
    ) throws -> DNSBoundHermesEventStreamingTransport {
        try DNSBoundHermesEventStreamingTransport(
            maximumRedirects: maximumRedirects,
            resolver: resolver,
            connectionFactory: factory
        )
    }

    private func privateEndpoint() throws -> ValidatedEndpoint {
        try EndpointValidator.validate(
            "https://provider.internal/api",
            declaredBoundary: .privateNetwork
        )
    }

    private func assertStreamOpenFailure(
        _ transport: DNSBoundHermesEventStreamingTransport,
        equals expected: NetworkTerminalError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await transport.stream(
                try ProviderRequest(method: .get, relativePath: "/events"),
                to: try privateEndpoint(),
                credential: nil
            )
            XCTFail("Expected stream-open failure", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? NetworkTerminalError, expected, file: file, line: line)
        }
    }

    private func collect(_ stream: AsyncThrowingStream<Data, Error>) async throws -> Data {
        var result = Data()
        for try await chunk in stream { result.append(chunk) }
        return result
    }
}

private actor SequencedHermesResolver: DNSBoundAddressResolving {
    private var answers: [[String]]
    private(set) var hostnames: [String] = []

    init(_ answers: [String]...) {
        self.answers = answers
    }

    func resolve(hostname: String) async throws -> [String] {
        hostnames.append(hostname)
        guard !answers.isEmpty else { return [] }
        return answers.removeFirst()
    }
}

private final class ScriptedHermesConnectionFactory: DNSBoundHermesConnectionCreating, @unchecked Sendable {
    private let lock = NSLock()
    private var connections: [ScriptedHermesConnection]
    private var storedAddresses: [String] = []
    private var storedMakeCount = 0

    init(_ connections: [ScriptedHermesConnection]) {
        self.connections = connections
    }

    var createdAddresses: [String] { lock.withLock { storedAddresses } }
    var makeCount: Int { lock.withLock { storedMakeCount } }

    func makeConnection(
        plan: DNSBoundConnectionPlan,
        address: DNSBoundIPAddress
    ) throws -> any DNSBoundHermesConnection {
        try lock.withLock {
            storedMakeCount += 1
            storedAddresses.append(address.literal)
            guard !connections.isEmpty else {
                throw NetworkTerminalError.connection(.unknown)
            }
            return connections.removeFirst()
        }
    }
}

private final class ScriptedHermesConnection: DNSBoundHermesConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var receives: [DNSBoundHermesConnectionReceive]
    private var waiter: CheckedContinuation<DNSBoundHermesConnectionReceive, Error>?
    private var storedRequests: [Data] = []
    private var storedCancelCount = 0
    private var cancelled = false
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

    init(_ receives: [DNSBoundHermesConnectionReceive]) {
        self.receives = receives
    }

    var sentRequests: [Data] { lock.withLock { storedRequests } }
    var cancelCount: Int { lock.withLock { storedCancelCount } }

    func start() async throws {
        if lock.withLock({ cancelled }) { throw NetworkTerminalError.cancelled }
    }

    func send(_ data: Data) async throws {
        try lock.withLock {
            guard !cancelled else { throw NetworkTerminalError.cancelled }
            storedRequests.append(data)
        }
    }

    func receive(maximumLength: Int) async throws -> DNSBoundHermesConnectionReceive {
        guard maximumLength > 0 else {
            throw DNSBoundHermesEventStreamingTransportError.invalidReceiveLimit
        }
        return try await withCheckedThrowingContinuation { continuation in
            enum Action {
                case wait
                case value(DNSBoundHermesConnectionReceive)
                case cancelled
            }
            let action = lock.withLock { () -> Action in
                guard !cancelled else { return .cancelled }
                guard !receives.isEmpty else {
                    waiter = continuation
                    return .wait
                }
                return .value(receives.removeFirst())
            }
            switch action {
            case .wait:
                break
            case let .value(value):
                continuation.resume(returning: value)
            case .cancelled:
                continuation.resume(throwing: NetworkTerminalError.cancelled)
            }
        }
    }

    func cancel() {
        let resources = lock.withLock { () -> (
            CheckedContinuation<DNSBoundHermesConnectionReceive, Error>?,
            [CheckedContinuation<Void, Never>]
        )? in
            guard !cancelled else { return nil }
            cancelled = true
            storedCancelCount += 1
            defer {
                waiter = nil
                cancellationWaiters.removeAll()
            }
            return (waiter, cancellationWaiters)
        }
        resources?.0?.resume(throwing: NetworkTerminalError.cancelled)
        resources?.1.forEach { $0.resume() }
    }

    func waitUntilCancelled() async {
        await withCheckedContinuation { continuation in
            let resumeImmediately = lock.withLock { () -> Bool in
                guard !cancelled else { return true }
                cancellationWaiters.append(continuation)
                return false
            }
            if resumeImmediately {
                continuation.resume()
            }
        }
    }
}

private func receive(_ value: String, complete: Bool) -> DNSBoundHermesConnectionReceive {
    DNSBoundHermesConnectionReceive(data: Data(value.utf8), isComplete: complete)
}

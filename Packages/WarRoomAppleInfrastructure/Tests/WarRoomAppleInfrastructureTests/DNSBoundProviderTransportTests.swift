import Foundation
import XCTest
@testable import WarRoomAppleInfrastructure
import WarRoomCore

final class DNSBoundProviderTransportTests: XCTestCase {
    func testGETResolvesValidatesConnectsToNumericPeerThenInjectsCredential() async throws {
        let trace = Trace()
        let resolver = ScriptedResolver(batches: [["10.0.0.7"]], trace: trace)
        let connection = ScriptedConnection(
            responses: [.bytes(http(status: 200, body: Data("ok".utf8)), complete: true)],
            trace: trace
        )
        let factory = ScriptedFactory(connections: [connection], trace: trace)
        let transport = try makeTransport(resolver: resolver, factory: factory)
        let endpoint = try privateEndpoint()
        let request = try ProviderRequest(method: .get, relativePath: "/v1/status")

        let response = try await transport.send(
            request,
            to: endpoint,
            credential: ProviderCredential(bytes: Data("unit-secret".utf8))
        )

        XCTAssertEqual(response, ProviderResponse(statusCode: 200, body: Data("ok".utf8)))
        let hostnames = await resolver.hostnames
        XCTAssertEqual(hostnames, ["provider.internal"])
        XCTAssertEqual(factory.addresses, ["10.0.0.7"])
        let requestText = try XCTUnwrap(String(data: connection.sent.single, encoding: .utf8))
        XCTAssertTrue(requestText.hasPrefix("GET /v1/status HTTP/1.1\r\n"))
        XCTAssertTrue(requestText.contains("Host: provider.internal\r\n"))
        XCTAssertTrue(requestText.contains("Authorization: Bearer unit-secret\r\n"))
        XCTAssertEqual(trace.values.prefix(3), ["resolve", "factory", "send"])
        XCTAssertEqual(connection.cancelCount, 1)
    }

    func testPOSTSerializesBoundedBodyAndQuery() async throws {
        let resolver = ScriptedResolver(batches: [["10.0.0.8"]])
        let connection = ScriptedConnection(
            responses: [.bytes(http(status: 201, body: Data()), complete: true)]
        )
        let transport = try makeTransport(
            resolver: resolver,
            factory: ScriptedFactory(connections: [connection])
        )
        let item = try ProviderQueryItem(name: "model", value: "local-1")
        let request = try ProviderRequest(
            method: .post,
            relativePath: "/v1/runs",
            queryItems: [item],
            body: Data("{}".utf8)
        )

        let response = try await transport.send(request, to: privateEndpoint(), credential: nil)

        XCTAssertEqual(response.statusCode, 201)
        let requestText = try XCTUnwrap(String(data: connection.sent.single, encoding: .utf8))
        XCTAssertTrue(requestText.hasPrefix("POST /v1/runs?model=local-1 HTTP/1.1\r\n"))
        XCTAssertTrue(requestText.contains("Content-Type: application/json\r\n"))
        XCTAssertTrue(requestText.contains("Content-Length: 2\r\n\r\n{}"))
    }

    func testSameOriginRedirectReResolvesRevalidatesReconnectsAndReinjectsCredential() async throws {
        let trace = Trace()
        let resolver = ScriptedResolver(
            batches: [["10.0.0.7"], ["10.0.0.9"]],
            trace: trace
        )
        let first = ScriptedConnection(
            responses: [.bytes(redirect(status: 307, location: "/v2/runs"), complete: true)],
            trace: trace
        )
        let second = ScriptedConnection(
            responses: [.bytes(http(status: 200, body: Data("done".utf8)), complete: true)],
            trace: trace
        )
        let factory = ScriptedFactory(connections: [first, second], trace: trace)
        let transport = try makeTransport(resolver: resolver, factory: factory)
        let request = try ProviderRequest(
            method: .post,
            relativePath: "/v1/runs",
            body: Data("{}".utf8)
        )

        let response = try await transport.send(
            request,
            to: privateEndpoint(),
            credential: ProviderCredential(bytes: Data("redirect-secret".utf8))
        )

        XCTAssertEqual(response.body, Data("done".utf8))
        let hostnames = await resolver.hostnames
        XCTAssertEqual(hostnames, ["provider.internal", "provider.internal"])
        XCTAssertEqual(factory.addresses, ["10.0.0.7", "10.0.0.9"])
        for connection in [first, second] {
            let text = try XCTUnwrap(String(data: connection.sent.single, encoding: .utf8))
            XCTAssertTrue(text.contains("Authorization: Bearer redirect-secret\r\n"))
        }
        let secondText = try XCTUnwrap(String(data: second.sent.single, encoding: .utf8))
        XCTAssertTrue(secondText.hasPrefix("POST /v2/runs HTTP/1.1\r\n"))
        XCTAssertTrue(secondText.hasSuffix("{}"))
        XCTAssertEqual(
            trace.values,
            ["resolve", "factory", "send", "resolve", "factory", "send"]
        )
    }

    func test303RedirectChangesPOSTToGETAndDropsBody() async throws {
        let resolver = ScriptedResolver(batches: [["10.0.0.7"], ["10.0.0.8"]])
        let first = ScriptedConnection(
            responses: [.bytes(redirect(status: 303, location: "/result"), complete: true)]
        )
        let second = ScriptedConnection(
            responses: [.bytes(http(status: 200, body: Data()), complete: true)]
        )
        let transport = try makeTransport(
            resolver: resolver,
            factory: ScriptedFactory(connections: [first, second])
        )
        let request = try ProviderRequest(
            method: .post,
            relativePath: "/submit",
            body: Data("payload".utf8)
        )

        _ = try await transport.send(request, to: privateEndpoint(), credential: nil)

        let redirected = try XCTUnwrap(String(data: second.sent.single, encoding: .utf8))
        XCTAssertTrue(redirected.hasPrefix("GET /result HTTP/1.1\r\n"))
        XCTAssertFalse(redirected.contains("Content-Length"))
        XCTAssertTrue(redirected.hasSuffix("\r\n\r\n"))
    }

    func testCrossOriginRedirectIsRejectedBeforeSecondResolutionOrCredentialReuse() async throws {
        let resolver = ScriptedResolver(batches: [["10.0.0.7"]])
        let first = ScriptedConnection(
            responses: [
                .bytes(
                    redirect(status: 302, location: "https://other.internal/steal"),
                    complete: true
                ),
            ]
        )
        let factory = ScriptedFactory(connections: [first])
        let transport = try makeTransport(resolver: resolver, factory: factory)

        await assertTransportError(
            .redirectedAcrossOrigin,
            operation: {
                try await transport.send(
                    ProviderRequest(method: .get, relativePath: "/start"),
                    to: self.privateEndpoint(),
                    credential: ProviderCredential(bytes: Data("secret".utf8))
                )
            }
        )
        let hostnameCount = await resolver.hostnames.count
        XCTAssertEqual(hostnameCount, 1)
        XCTAssertEqual(factory.makeCount, 1)
    }

    func testSchemeAndEffectivePortChangesAreRejected() async throws {
        let locations = [
            "http://provider.internal/next",
            "https://provider.internal:8443/next",
        ]
        for location in locations {
            let resolver = ScriptedResolver(batches: [["10.0.0.7"]])
            let connection = ScriptedConnection(
                responses: [.bytes(redirect(status: 302, location: location), complete: true)]
            )
            let transport = try makeTransport(
                resolver: resolver,
                factory: ScriptedFactory(connections: [connection])
            )
            await assertTransportError(.redirectedAcrossOrigin) {
                try await transport.send(
                    ProviderRequest(method: .get, relativePath: "/start"),
                    to: self.privateEndpoint(),
                    credential: nil
                )
            }
        }
    }

    func testRedirectLimitIsEnforced() async throws {
        let resolver = ScriptedResolver(batches: [["10.0.0.7"]])
        let connection = ScriptedConnection(
            responses: [.bytes(redirect(status: 307, location: "/again"), complete: true)]
        )
        let policy = try DNSBoundProviderTransportPolicy(maximumRedirects: 0)
        let transport = DNSBoundProviderTransport(
            policy: policy,
            resolver: resolver,
            connectionFactory: ScriptedFactory(connections: [connection]),
            clock: SuspendingClock()
        )

        await assertTransportError(.tooManyRedirects(limit: 0)) {
            try await transport.send(
                ProviderRequest(method: .get, relativePath: "/start"),
                to: self.privateEndpoint(),
                credential: nil
            )
        }
    }

    func testRedirectWithoutExactlyOneLocationIsRejected() async throws {
        let responses = [
            Data("HTTP/1.1 302 Redirect\r\nContent-Length: 0\r\n\r\n".utf8),
            Data(
                "HTTP/1.1 302 Redirect\r\nLocation: /one\r\nLocation: /two\r\nContent-Length: 0\r\n\r\n".utf8
            ),
        ]
        for response in responses {
            let connection = ScriptedConnection(
                responses: [.bytes(response, complete: true)]
            )
            let transport = try makeTransport(
                resolver: ScriptedResolver(batches: [["10.0.0.7"]]),
                factory: ScriptedFactory(connections: [connection])
            )
            await assertTransportError(.invalidRedirect) {
                try await transport.send(
                    ProviderRequest(method: .get, relativePath: "/start"),
                    to: self.privateEndpoint(),
                    credential: nil
                )
            }
        }
    }

    func testRequestBodyLimitRejectsBeforeResolutionOrCredentialRead() async throws {
        let resolver = ScriptedResolver(batches: [])
        let transportPolicy = try ProviderTransportPolicy(
            maximumRequestBodyBytes: 1,
            maximumResponseBodyBytes: 32,
            requestTimeout: 5,
            resourceTimeout: 5
        )
        let transport = DNSBoundProviderTransport(
            policy: try DNSBoundProviderTransportPolicy(transport: transportPolicy),
            resolver: resolver,
            connectionFactory: ScriptedFactory(connections: []),
            clock: SuspendingClock()
        )
        await assertTransportError(.requestBodyTooLarge(limit: 1)) {
            try await transport.send(
                ProviderRequest(
                    method: .post,
                    relativePath: "/submit",
                    body: Data("{}".utf8)
                ),
                to: self.privateEndpoint(),
                credential: ProviderCredential(bytes: Data("must-not-read".utf8))
            )
        }
        let hostnames = await resolver.hostnames
        XCTAssertTrue(hostnames.isEmpty)
    }

    func testResponseBodyLimitFailsClosedWithRedactedProtocolError() async throws {
        let transportPolicy = try ProviderTransportPolicy(
            maximumRequestBodyBytes: 32,
            maximumResponseBodyBytes: 2,
            requestTimeout: 5,
            resourceTimeout: 5
        )
        let policy = try DNSBoundProviderTransportPolicy(transport: transportPolicy)
        let connection = ScriptedConnection(
            responses: [.bytes(http(status: 200, body: Data("toolong".utf8)), complete: true)]
        )
        let transport = DNSBoundProviderTransport(
            policy: policy,
            resolver: ScriptedResolver(batches: [["10.0.0.7"]]),
            connectionFactory: ScriptedFactory(connections: [connection]),
            clock: SuspendingClock()
        )

        await assertTransportError(.terminal(.protocolFailure(.bodyLimitExceeded))) {
            try await transport.send(
                ProviderRequest(method: .get, relativePath: "/large"),
                to: self.privateEndpoint(),
                credential: nil
            )
        }
        XCTAssertEqual(connection.cancelCount, 1)
    }

    func testInvalidCredentialIsReadOnlyAfterResolutionAndConnectionConstruction() async throws {
        let trace = Trace()
        let resolver = ScriptedResolver(batches: [["10.0.0.7"]], trace: trace)
        let connection = ScriptedConnection(responses: [], trace: trace)
        let factory = ScriptedFactory(connections: [connection], trace: trace)
        let transport = try makeTransport(resolver: resolver, factory: factory)

        await assertTransportError(.invalidCredential) {
            try await transport.send(
                ProviderRequest(method: .get, relativePath: "/status"),
                to: self.privateEndpoint(),
                credential: ProviderCredential(bytes: Data([0x0A]))
            )
        }
        XCTAssertEqual(trace.values, ["resolve", "factory"])
        XCTAssertTrue(connection.sent.values.isEmpty)
    }

    func testResolutionBoundaryFailurePreventsConnectionAndCredentialInjection() async throws {
        let factory = ScriptedFactory(connections: [])
        let transport = try makeTransport(
            resolver: ScriptedResolver(batches: [["8.8.8.8"]]),
            factory: factory
        )

        await assertTransportError(
            .planning(.boundaryMismatch(declared: .privateNetwork, resolved: .global))
        ) {
            try await transport.send(
                ProviderRequest(method: .get, relativePath: "/status"),
                to: self.privateEndpoint(),
                credential: ProviderCredential(bytes: Data("must-not-send".utf8))
            )
        }
        XCTAssertEqual(factory.makeCount, 0)
    }

    func testCancellationCancelsHangingConnectionExactlyOnce() async throws {
        let connection = ScriptedConnection(responses: [])
        let transport = try makeTransport(
            resolver: ScriptedResolver(batches: [["10.0.0.7"]]),
            factory: ScriptedFactory(connections: [connection])
        )
        let task = Task {
            try await transport.send(
                ProviderRequest(method: .get, relativePath: "/hang"),
                to: try privateEndpoint(),
                credential: nil
            )
        }
        await waitUntil { !connection.sent.values.isEmpty }

        task.cancel()
        switch await task.result {
        case .success:
            XCTFail("Expected cancellation")
        case let .failure(error):
            XCTAssertEqual(
                error as? DNSBoundProviderTransportError,
                .terminal(.cancelled)
            )
        }
        XCTAssertEqual(connection.cancelCount, 1)
        connection.emit(.failed(.connectionReset))
        XCTAssertEqual(connection.cancelCount, 1)
    }

    func testTimeoutCancelsHangingConnectionExactlyOnce() async throws {
        let connection = ScriptedConnection(responses: [])
        let transport = DNSBoundProviderTransport(
            policy: .secureDefault,
            resolver: ScriptedResolver(batches: [["10.0.0.7"]]),
            connectionFactory: ScriptedFactory(connections: [connection]),
            clock: ImmediateClock()
        )

        await assertTransportError(.terminal(.timedOut)) {
            try await transport.send(
                ProviderRequest(method: .get, relativePath: "/hang"),
                to: self.privateEndpoint(),
                credential: nil
            )
        }
        XCTAssertEqual(connection.cancelCount, 1)
        connection.emit(.failed(.networkUnavailable))
        XCTAssertEqual(connection.cancelCount, 1)
    }

    func testDeleteIsRejectedBeforeResolution() async throws {
        let resolver = ScriptedResolver(batches: [])
        let transport = try makeTransport(
            resolver: resolver,
            factory: ScriptedFactory(connections: [])
        )
        await assertTransportError(.unsupportedMethod) {
            try await transport.send(
                ProviderRequest(method: .delete, relativePath: "/resource"),
                to: self.privateEndpoint(),
                credential: nil
            )
        }
        let hostnames = await resolver.hostnames
        XCTAssertTrue(hostnames.isEmpty)
    }

    func testErrorsHaveConstantRedactedDescriptions() {
        let errors: [DNSBoundProviderTransportError] = [
            .invalidPolicy,
            .unsupportedMethod,
            .invalidRelativePath,
            .invalidCredential,
            .requestBodyTooLarge(limit: 1),
            .redirectedAcrossOrigin,
            .invalidRedirect,
            .tooManyRedirects(limit: 1),
            .planning(.noResolvedAddresses),
            .terminal(.connection(.tlsHandshake)),
            .protocolFailure(.invalidHeader),
        ]
        for error in errors {
            XCTAssertEqual(String(describing: error), "DNSBoundProviderTransportError(<redacted>)")
            XCTAssertEqual(String(reflecting: error), "DNSBoundProviderTransportError(<redacted>)")
            XCTAssertFalse(error.localizedDescription.contains("provider.internal"))
            XCTAssertFalse(error.localizedDescription.contains("secret"))
        }
    }

    private func makeTransport(
        resolver: ScriptedResolver,
        factory: ScriptedFactory
    ) throws -> DNSBoundProviderTransport {
        DNSBoundProviderTransport(
            policy: try DNSBoundProviderTransportPolicy(),
            resolver: resolver,
            connectionFactory: factory,
            clock: SuspendingClock()
        )
    }

    private func privateEndpoint() throws -> ValidatedEndpoint {
        try EndpointValidator.validate(
            "https://provider.internal",
            declaredBoundary: .privateNetwork
        )
    }

    private func assertTransportError(
        _ expected: DNSBoundProviderTransportError,
        operation: () async throws -> ProviderResponse,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected transport failure", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? DNSBoundProviderTransportError, expected, file: file, line: line)
        }
    }

    private func waitUntil(
        attempts: Int = 100,
        condition: @escaping @Sendable () -> Bool
    ) async {
        for _ in 0..<attempts {
            if condition() { return }
            await Task.yield()
        }
    }
}

private func http(status: Int, body: Data) -> Data {
    var data = Data("HTTP/1.1 \(status) Test\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
    data.append(body)
    return data
}

private func redirect(status: Int, location: String) -> Data {
    Data(
        "HTTP/1.1 \(status) Redirect\r\nLocation: \(location)\r\nContent-Length: 0\r\n\r\n".utf8
    )
}

private actor ScriptedResolver: DNSBoundAddressResolving {
    private var batches: [[String]]
    private let trace: Trace?
    private(set) var hostnames: [String] = []

    init(batches: [[String]], trace: Trace? = nil) {
        self.batches = batches
        self.trace = trace
    }

    func resolve(hostname: String) async throws -> [String] {
        hostnames.append(hostname)
        trace?.append("resolve")
        guard !batches.isEmpty else { return [] }
        return batches.removeFirst()
    }
}

private final class ScriptedFactory: DNSBoundTransportConnectionFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var connections: [ScriptedConnection]
    private let trace: Trace?
    private var storedAddresses: [String] = []
    private var storedMakeCount = 0

    init(connections: [ScriptedConnection], trace: Trace? = nil) {
        self.connections = connections
        self.trace = trace
    }

    var addresses: [String] { lock.withLock { storedAddresses } }
    var makeCount: Int { lock.withLock { storedMakeCount } }

    func makeConnection(
        plan: DNSBoundConnectionPlan,
        address: DNSBoundIPAddress
    ) throws -> any DNSBoundTransportConnection {
        try lock.withLock {
            storedMakeCount += 1
            storedAddresses.append(address.literal)
            trace?.append("factory")
            guard !connections.isEmpty else { throw FactoryFailure.noConnection }
            return connections.removeFirst()
        }
    }
}

private enum FactoryFailure: Error {
    case noConnection
}

private final class ScriptedConnection: DNSBoundTransportConnection, @unchecked Sendable {
    enum Response {
        case bytes(Data, complete: Bool)
        case failure(NetworkConnectionFailure)
    }

    private let lock = NSLock()
    private var stateHandler: (@Sendable (DNSBoundTransportConnectionState) -> Void)?
    private var responses: [Response]
    private let trace: Trace?
    private let storedSent = LockedValues<Data>()
    private var storedCancelCount = 0

    init(responses: [Response], trace: Trace? = nil) {
        self.responses = responses
        self.trace = trace
    }

    var sent: LockedValues<Data> { storedSent }
    var cancelCount: Int { lock.withLock { storedCancelCount } }

    func setStateHandler(
        _ handler: @escaping @Sendable (DNSBoundTransportConnectionState) -> Void
    ) {
        lock.withLock { stateHandler = handler }
    }

    func start() {
        emit(.ready)
    }

    func send(
        _ content: Data,
        completion: @escaping @Sendable (NetworkConnectionFailure?) -> Void
    ) {
        storedSent.append(content)
        trace?.append("send")
        completion(nil)
    }

    func receive(
        maximumLength: Int,
        completion: @escaping @Sendable (Data?, Bool, NetworkConnectionFailure?) -> Void
    ) {
        let response = lock.withLock { responses.isEmpty ? nil : responses.removeFirst() }
        switch response {
        case let .bytes(data, complete):
            XCTAssertGreaterThan(maximumLength, 0)
            completion(data, complete, nil)
        case let .failure(failure):
            completion(nil, false, failure)
        case nil:
            break
        }
    }

    func cancel() {
        lock.withLock { storedCancelCount += 1 }
    }

    func emit(_ state: DNSBoundTransportConnectionState) {
        let handler = lock.withLock { stateHandler }
        handler?(state)
    }
}

private final class Trace: @unchecked Sendable {
    private let storage = LockedValues<String>()
    var values: [String] { storage.values }
    func append(_ value: String) { storage.append(value) }
}

private final class LockedValues<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Value] = []
    var values: [Value] { lock.withLock { stored } }
    var single: Value { lock.withLock { stored[0] } }
    func append(_ value: Value) { lock.withLock { stored.append(value) } }
}

private struct SuspendingClock: DNSBoundTransportClock, Sendable {
    func nowNanoseconds() -> UInt64 { 1 }
    func sleep(nanoseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: UInt64.max)
    }
}

private struct ImmediateClock: DNSBoundTransportClock, Sendable {
    func nowNanoseconds() -> UInt64 { 1 }
    func sleep(nanoseconds: UInt64) async throws {}
}

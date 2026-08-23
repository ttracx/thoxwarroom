import Darwin
import Foundation
import Network
import WarRoomCore

/// Policy for the opt-in DNS-bound provider transport.
public struct DNSBoundProviderTransportPolicy: Equatable, Sendable {
    public let transport: ProviderTransportPolicy
    public let maximumRedirects: Int

    public init(
        transport: ProviderTransportPolicy = .secureDefault,
        maximumRedirects: Int = 5
    ) throws {
        guard maximumRedirects >= 0 else {
            throw DNSBoundProviderTransportError.invalidPolicy
        }
        self.transport = transport
        self.maximumRedirects = maximumRedirects
    }

    public static let secureDefault = DNSBoundProviderTransportPolicy(
        validatedTransport: .secureDefault,
        maximumRedirects: 5
    )

    private init(
        validatedTransport: ProviderTransportPolicy,
        maximumRedirects: Int
    ) {
        self.transport = validatedTransport
        self.maximumRedirects = maximumRedirects
    }
}

/// Typed transport failures whose descriptions never include URLs, headers,
/// credentials, response bodies, resolved addresses, or underlying error text.
public enum DNSBoundProviderTransportError: Error, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible
{
    case invalidPolicy
    case unsupportedMethod
    case invalidRelativePath
    case invalidCredential
    case requestBodyTooLarge(limit: Int)
    case redirectedAcrossOrigin
    case invalidRedirect
    case tooManyRedirects(limit: Int)
    case planning(DNSBoundConnectionError)
    case terminal(NetworkTerminalError)
    case protocolFailure(NetworkProtocolFailure)

    public var description: String { "DNSBoundProviderTransportError(<redacted>)" }
    public var debugDescription: String { description }
}

/// A minimal connection seam used to make Network.framework execution fully
/// deterministic in unit tests without weakening production TLS behavior.
protocol DNSBoundTransportConnection: Sendable {
    func setStateHandler(
        _ handler: @escaping @Sendable (DNSBoundTransportConnectionState) -> Void
    )
    func start()
    func send(
        _ content: Data,
        completion: @escaping @Sendable (NetworkConnectionFailure?) -> Void
    )
    func receive(
        maximumLength: Int,
        completion: @escaping @Sendable (Data?, Bool, NetworkConnectionFailure?) -> Void
    )
    func cancel()
}

enum DNSBoundTransportConnectionState: Sendable, Equatable {
    case preparing
    case ready
    case waiting(NetworkConnectionFailure)
    case failed(NetworkConnectionFailure)
    case cancelled
}

protocol DNSBoundTransportConnectionFactory: Sendable {
    func makeConnection(
        plan: DNSBoundConnectionPlan,
        address: DNSBoundIPAddress
    ) throws -> any DNSBoundTransportConnection
}

struct SystemDNSBoundTransportConnectionFactory: DNSBoundTransportConnectionFactory, Sendable {
    func makeConnection(
        plan: DNSBoundConnectionPlan,
        address: DNSBoundIPAddress
    ) throws -> any DNSBoundTransportConnection {
        SystemDNSBoundTransportConnection(connection: try plan.makeConnection(to: address))
    }
}

protocol DNSBoundTransportClock: Sendable {
    func nowNanoseconds() -> UInt64
    func sleep(nanoseconds: UInt64) async throws
}

struct SystemDNSBoundTransportClock: DNSBoundTransportClock, Sendable {
    func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    func sleep(nanoseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

/// Opt-in provider transport that closes the DNS rebinding window by resolving
/// and validating every hop before connecting to an approved numeric peer.
/// The connection plan retains the original hostname for SNI and default trust.
public struct DNSBoundProviderTransport: ProviderTransport, Sendable {
    private let policy: DNSBoundProviderTransportPolicy
    private let planner: DNSBoundConnectionPlanner
    private let connectionFactory: any DNSBoundTransportConnectionFactory
    private let clock: any DNSBoundTransportClock

    public init(policy: DNSBoundProviderTransportPolicy = .secureDefault) {
        self.policy = policy
        self.planner = DNSBoundConnectionPlanner()
        self.connectionFactory = SystemDNSBoundTransportConnectionFactory()
        self.clock = SystemDNSBoundTransportClock()
    }

    init(
        policy: DNSBoundProviderTransportPolicy,
        resolver: any DNSBoundAddressResolving,
        connectionFactory: any DNSBoundTransportConnectionFactory,
        clock: any DNSBoundTransportClock
    ) {
        self.policy = policy
        self.planner = DNSBoundConnectionPlanner(resolver: resolver)
        self.connectionFactory = connectionFactory
        self.clock = clock
    }

    public func send(
        _ request: ProviderRequest,
        to endpoint: ValidatedEndpoint,
        credential: ProviderCredential?
    ) async throws -> ProviderResponse {
        do {
            return try await execute(request, to: endpoint, credential: credential)
        } catch let error as DNSBoundProviderTransportError {
            throw error
        } catch is CancellationError {
            throw DNSBoundProviderTransportError.terminal(.cancelled)
        } catch {
            throw DNSBoundProviderTransportError.terminal(.connection(.unknown))
        }
    }

    private func execute(
        _ request: ProviderRequest,
        to endpoint: ValidatedEndpoint,
        credential: ProviderCredential?
    ) async throws -> ProviderResponse {
        guard request.method == .get || request.method == .post else {
            throw DNSBoundProviderTransportError.unsupportedMethod
        }
        if let body = request.body,
           body.count > policy.transport.maximumRequestBodyBytes {
            throw DNSBoundProviderTransportError.requestBodyTooLarge(
                limit: policy.transport.maximumRequestBodyBytes
            )
        }

        let initialURL = try makeInitialURL(request: request, endpoint: endpoint)
        let origin = DNSBoundOrigin(endpoint.url)
        let deadline = adding(
            seconds: policy.transport.resourceTimeout,
            to: clock.nowNanoseconds()
        )
        var hop = HopRequest(
            method: request.method.rawValue,
            url: initialURL,
            body: request.body ?? Data()
        )
        var redirectCount = 0

        while true {
            try Task.checkCancellation()
            try validateHop(hop.url, origin: origin)
            let now = clock.nowNanoseconds()
            guard now < deadline else {
                throw DNSBoundProviderTransportError.terminal(.timedOut)
            }
            let hopDeadline = min(
                deadline,
                adding(seconds: policy.transport.requestTimeout, to: now)
            )

            // Planning (including a fresh DNS lookup and complete address-set
            // validation) and connection construction both happen before the
            // credential is read and injected into request bytes.
            let plan: DNSBoundConnectionPlan
            do {
                plan = try await planConnection(
                    for: endpoint,
                    timeoutNanoseconds: hopDeadline - now
                )
            } catch let error as DNSBoundConnectionError {
                throw DNSBoundProviderTransportError.planning(error)
            }
            try Task.checkCancellation()
            let postPlanningNow = clock.nowNanoseconds()
            guard postPlanningNow < hopDeadline else {
                throw DNSBoundProviderTransportError.terminal(.timedOut)
            }
            guard let address = plan.addresses.first else {
                throw DNSBoundProviderTransportError.planning(.noResolvedAddresses)
            }
            let connection: any DNSBoundTransportConnection
            do {
                connection = try connectionFactory.makeConnection(plan: plan, address: address)
            } catch let error as DNSBoundConnectionError {
                throw DNSBoundProviderTransportError.planning(error)
            } catch {
                throw DNSBoundProviderTransportError.terminal(.connection(.unknown))
            }

            let wireRequest: Data
            do {
                wireRequest = try makeWireRequest(
                    hop: hop,
                    plan: plan,
                    credential: credential
                )
            } catch {
                // Connection construction intentionally precedes credential
                // access. If serialization rejects the credential or request,
                // release that not-yet-started connection before propagating.
                connection.cancel()
                throw error
            }
            let result = try await performHop(
                connection: connection,
                wireRequest: wireRequest,
                requestMethod: hop.method,
                timeoutNanoseconds: hopDeadline - postPlanningNow
            )

            guard Self.isRedirect(result.head.statusCode) else {
                return ProviderResponse(statusCode: result.head.statusCode, body: result.body)
            }
            guard redirectCount < policy.maximumRedirects else {
                throw DNSBoundProviderTransportError.tooManyRedirects(
                    limit: policy.maximumRedirects
                )
            }
            let redirectURL = try redirectDestination(from: result.head, relativeTo: hop.url)
            try validateHop(redirectURL, origin: origin)
            redirectCount += 1
            hop = redirectedRequest(from: hop, statusCode: result.head.statusCode, url: redirectURL)
        }
    }

    private func planConnection(
        for endpoint: ValidatedEndpoint,
        timeoutNanoseconds: UInt64
    ) async throws -> DNSBoundConnectionPlan {
        try await withThrowingTaskGroup(of: DNSBoundPlanningOutcome.self) { group in
            group.addTask { [planner] in
                .plan(try await planner.plan(for: endpoint))
            }
            group.addTask { [clock] in
                try await clock.sleep(nanoseconds: timeoutNanoseconds)
                return .timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw DNSBoundProviderTransportError.terminal(.connection(.unknown))
            }
            switch first {
            case let .plan(plan):
                return plan
            case .timedOut:
                throw DNSBoundProviderTransportError.terminal(.timedOut)
            }
        }
    }

    private func performHop(
        connection: any DNSBoundTransportConnection,
        wireRequest: Data,
        requestMethod: String,
        timeoutNanoseconds: UInt64
    ) async throws -> HopResponse {
        let limits: BoundedHTTP1Limits
        do {
            limits = try BoundedHTTP1Limits(
                maximumBodyBytes: policy.transport.maximumResponseBodyBytes,
                maximumDeliveryBytes: max(
                    1,
                    min(16 * 1_024, policy.transport.maximumResponseBodyBytes)
                )
            )
        } catch {
            throw DNSBoundProviderTransportError.invalidPolicy
        }

        let coordinator: NetworkTerminalStateCoordinator<HopResponse, Data>
        do {
            coordinator = try NetworkTerminalStateCoordinator(
                bufferingLimit: 1,
                cancelConnection: { connection.cancel() }
            )
        } catch let error as NetworkTerminalError {
            throw DNSBoundProviderTransportError.terminal(error)
        }
        let driver: DNSBoundHopDriver
        do {
            driver = try DNSBoundHopDriver(
                connection: connection,
                coordinator: coordinator,
                request: wireRequest,
                requestMethod: requestMethod,
                limits: limits
            )
        } catch let error as BoundedHTTP1Error {
            throw DNSBoundProviderTransportError.protocolFailure(Self.mapProtocol(error))
        }

        connection.setStateHandler { state in
            driver.handle(state)
        }
        connection.start()
        let timeoutTask = Task { [clock] in
            do {
                try await clock.sleep(nanoseconds: timeoutNanoseconds)
                coordinator.timeout()
            } catch {
                // Cancelling the timer is an expected post-terminal cleanup path.
            }
        }
        defer { timeoutTask.cancel() }

        do {
            return try await coordinator.awaitResponse()
        } catch let error as NetworkTerminalError {
            throw DNSBoundProviderTransportError.terminal(error)
        }
    }

    private func makeInitialURL(
        request: ProviderRequest,
        endpoint: ValidatedEndpoint
    ) throws -> URL {
        guard var components = URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false) else {
            throw DNSBoundProviderTransportError.invalidRelativePath
        }
        let basePath = components.percentEncodedPath.hasSuffix("/")
            ? String(components.percentEncodedPath.dropLast())
            : components.percentEncodedPath
        components.percentEncodedPath = basePath + request.relativePath
        components.queryItems = request.queryItems.isEmpty ? nil : request.queryItems.map {
            URLQueryItem(name: $0.name, value: $0.value)
        }
        components.fragment = nil
        guard let url = components.url else {
            throw DNSBoundProviderTransportError.invalidRelativePath
        }
        try validateHop(url, origin: DNSBoundOrigin(endpoint.url))
        return url
    }

    private func validateHop(_ url: URL, origin: DNSBoundOrigin) throws {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              url.fragment == nil,
              DNSBoundOrigin(url) == origin else {
            throw DNSBoundProviderTransportError.redirectedAcrossOrigin
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              !components.percentEncodedPath.hasPrefix("//"),
              !components.percentEncodedPath.contains("\\"),
              !(components.percentEncodedPath.removingPercentEncoding ?? components.percentEncodedPath)
                .split(separator: "/", omittingEmptySubsequences: false)
                .contains("..") else {
            throw DNSBoundProviderTransportError.invalidRelativePath
        }
    }

    private func makeWireRequest(
        hop: HopRequest,
        plan: DNSBoundConnectionPlan,
        credential: ProviderCredential?
    ) throws -> Data {
        var headers = [
            BoundedHTTP1Header(name: "Host", value: hostHeader(plan: plan)),
            BoundedHTTP1Header(name: "Accept", value: "application/json"),
            BoundedHTTP1Header(name: "Connection", value: "close"),
        ]
        if !hop.body.isEmpty {
            headers.append(BoundedHTTP1Header(name: "Content-Type", value: "application/json"))
        }
        if let credential {
            headers.append(
                BoundedHTTP1Header(
                    name: "Authorization",
                    value: "Bearer \(try bearerValue(from: credential))"
                )
            )
        }

        let components = try requireComponents(hop.url)
        let target = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        let targetWithQuery = components.percentEncodedQuery.map { target + "?" + $0 } ?? target
        let limits = try BoundedHTTP1Limits(
            maximumBodyBytes: policy.transport.maximumRequestBodyBytes,
            maximumDeliveryBytes: max(
                1,
                min(16 * 1_024, policy.transport.maximumRequestBodyBytes)
            )
        )
        do {
            return try BoundedHTTP1RequestSerializer.serialize(
                BoundedHTTP1Request(
                    method: hop.method,
                    target: targetWithQuery,
                    headers: headers,
                    body: hop.body
                ),
                limits: limits
            )
        } catch let error as BoundedHTTP1Error {
            throw DNSBoundProviderTransportError.protocolFailure(Self.mapProtocol(error))
        }
    }

    private func bearerValue(from credential: ProviderCredential) throws -> String {
        let bytes = credential.withUnsafeBytes { Data($0) }
        guard !bytes.isEmpty,
              !bytes.contains(0x0A),
              !bytes.contains(0x0D),
              bytes.allSatisfy({ $0 >= 0x20 && $0 != 0x7F }),
              let value = String(data: bytes, encoding: .utf8) else {
            throw DNSBoundProviderTransportError.invalidCredential
        }
        return value
    }

    private func requireComponents(_ url: URL) throws -> URLComponents {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw DNSBoundProviderTransportError.invalidRelativePath
        }
        return components
    }

    private func hostHeader(plan: DNSBoundConnectionPlan) -> String {
        let host = plan.serverName.contains(":") ? "[\(plan.serverName)]" : plan.serverName
        return plan.port == 443 ? host : "\(host):\(plan.port)"
    }

    private func redirectDestination(
        from head: BoundedHTTP1ResponseHead,
        relativeTo currentURL: URL
    ) throws -> URL {
        let locations = head.headers.filter {
            $0.name.caseInsensitiveCompare("location") == .orderedSame
        }
        guard locations.count == 1,
              !locations[0].value.isEmpty,
              let destination = URL(string: locations[0].value, relativeTo: currentURL)?.absoluteURL else {
            throw DNSBoundProviderTransportError.invalidRedirect
        }
        return destination
    }

    private func redirectedRequest(
        from request: HopRequest,
        statusCode: Int,
        url: URL
    ) -> HopRequest {
        switch statusCode {
        case 303:
            return HopRequest(method: "GET", url: url, body: Data())
        case 301 where request.method == "POST",
             302 where request.method == "POST":
            return HopRequest(method: "GET", url: url, body: Data())
        default:
            return HopRequest(method: request.method, url: url, body: request.body)
        }
    }

    private static func isRedirect(_ statusCode: Int) -> Bool {
        [301, 302, 303, 307, 308].contains(statusCode)
    }

    private func nanoseconds(_ interval: TimeInterval) -> UInt64 {
        let value = interval * 1_000_000_000
        if value >= Double(UInt64.max) { return UInt64.max }
        return UInt64(value.rounded(.down))
    }

    private func adding(seconds: TimeInterval, to value: UInt64) -> UInt64 {
        let increment = nanoseconds(seconds)
        let (result, overflow) = value.addingReportingOverflow(increment)
        return overflow ? UInt64.max : result
    }

    fileprivate static func mapProtocol(_ error: BoundedHTTP1Error) -> NetworkProtocolFailure {
        switch error {
        case .invalidStatusLine:
            return .malformedStatusLine
        case .invalidHeader, .tooManyHeaders, .headersTooLarge, .lineTooLong,
             .malformedLineEnding:
            return .invalidHeader
        case .bodyTooLarge, .requestTooLarge:
            return .bodyLimitExceeded
        case .unexpectedEndOfStream:
            return .unexpectedEndOfStream
        default:
            return .unsupportedFraming
        }
    }
}

private enum DNSBoundPlanningOutcome: Sendable {
    case plan(DNSBoundConnectionPlan)
    case timedOut
}

private struct DNSBoundOrigin: Equatable, Sendable {
    let scheme: String
    let host: String
    let port: Int

    init(_ url: URL) {
        scheme = url.scheme?.lowercased() ?? ""
        host = url.host?.lowercased() ?? ""
        port = url.port ?? (scheme == "https" ? 443 : 80)
    }
}

private struct HopRequest: Sendable {
    let method: String
    let url: URL
    let body: Data
}

private struct HopResponse: Sendable {
    let head: BoundedHTTP1ResponseHead
    let body: Data
}

private final class DNSBoundHopDriver: @unchecked Sendable {
    private struct State {
        var parser: BoundedHTTP1ResponseParser
        var head: BoundedHTTP1ResponseHead?
        var body = Data()
        var requestSent = false
        var receivePending = false
    }

    private let lock = NSLock()
    private let connection: any DNSBoundTransportConnection
    private let coordinator: NetworkTerminalStateCoordinator<HopResponse, Data>
    private let request: Data
    private var state: State

    init(
        connection: any DNSBoundTransportConnection,
        coordinator: NetworkTerminalStateCoordinator<HopResponse, Data>,
        request: Data,
        requestMethod: String,
        limits: BoundedHTTP1Limits
    ) throws {
        self.connection = connection
        self.coordinator = coordinator
        self.request = request
        self.state = State(
            parser: try BoundedHTTP1ResponseParser(
                requestMethod: requestMethod,
                limits: limits
            )
        )
    }

    func handle(_ connectionState: DNSBoundTransportConnectionState) {
        switch connectionState {
        case .preparing, .waiting:
            break
        case .ready:
            sendOnce()
        case let .failed(reason):
            coordinator.fail(.connection(reason))
        case .cancelled:
            coordinator.fail(.connection(.unknown))
        }
    }

    private func sendOnce() {
        let shouldSend = lock.withLock { () -> Bool in
            guard !state.requestSent else { return false }
            state.requestSent = true
            return true
        }
        guard shouldSend else { return }
        connection.send(request) { [weak self] failure in
            guard let self else { return }
            if let failure {
                self.coordinator.fail(.connection(failure))
            } else {
                self.receiveNext()
            }
        }
    }

    private func receiveNext() {
        guard !coordinator.snapshot().phase.isTerminal else { return }
        let shouldReceive = lock.withLock { () -> Bool in
            guard !state.receivePending else { return false }
            state.receivePending = true
            return true
        }
        guard shouldReceive else { return }
        connection.receive(maximumLength: 16 * 1_024) { [weak self] data, isComplete, failure in
            self?.handleReceive(data: data, isComplete: isComplete, failure: failure)
        }
    }

    private func handleReceive(
        data: Data?,
        isComplete: Bool,
        failure: NetworkConnectionFailure?
    ) {
        if let failure {
            lock.withLock { state.receivePending = false }
            coordinator.fail(.connection(failure))
            return
        }

        let outcome: Result<(HopResponse?, Bool), BoundedHTTP1Error> = lock.withLock {
            state.receivePending = false
            do {
                var events: [BoundedHTTP1ResponseEvent] = []
                if let data, !data.isEmpty {
                    events += try state.parser.receive(data)
                }
                if isComplete {
                    events += try state.parser.finishEOF()
                }
                var completed = false
                for event in events {
                    switch event {
                    case .informational:
                        break
                    case let .head(head):
                        state.head = head
                    case let .body(chunk):
                        state.body.append(chunk)
                    case .complete:
                        completed = true
                    }
                }
                if completed {
                    guard let head = state.head else {
                        return .failure(.unexpectedEndOfStream)
                    }
                    return .success((HopResponse(head: head, body: state.body), true))
                }
                return .success((nil, false))
            } catch let error as BoundedHTTP1Error {
                return .failure(error)
            } catch {
                return .failure(.unexpectedEndOfStream)
            }
        }

        switch outcome {
        case let .failure(error):
            coordinator.fail(.protocolFailure(DNSBoundProviderTransport.mapProtocol(error)))
        case let .success((response, completed)):
            if let response {
                _ = coordinator.publishResponse(response)
            }
            if completed {
                coordinator.finish()
            } else {
                receiveNext()
            }
        }
    }
}

private extension NetworkTerminalPhase {
    var isTerminal: Bool {
        if case .terminal = self { return true }
        return false
    }
}

private final class SystemDNSBoundTransportConnection: DNSBoundTransportConnection,
    @unchecked Sendable
{
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "ai.thox.warroom.dns-bound-provider")

    init(connection: NWConnection) {
        self.connection = connection
    }

    func setStateHandler(
        _ handler: @escaping @Sendable (DNSBoundTransportConnectionState) -> Void
    ) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .setup, .preparing:
                handler(.preparing)
            case .ready:
                handler(.ready)
            case let .waiting(error):
                handler(.waiting(Self.classify(error)))
            case let .failed(error):
                handler(.failed(Self.classify(error)))
            case .cancelled:
                handler(.cancelled)
            @unknown default:
                handler(.failed(.unknown))
            }
        }
    }

    func start() {
        connection.start(queue: queue)
    }

    func send(
        _ content: Data,
        completion: @escaping @Sendable (NetworkConnectionFailure?) -> Void
    ) {
        connection.send(content: content, completion: .contentProcessed { error in
            completion(error.map(Self.classify))
        })
    }

    func receive(
        maximumLength: Int,
        completion: @escaping @Sendable (Data?, Bool, NetworkConnectionFailure?) -> Void
    ) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: maximumLength
        ) { content, _, isComplete, error in
            completion(content, isComplete, error.map(Self.classify))
        }
    }

    func cancel() {
        connection.cancel()
    }

    private static func classify(_ error: NWError) -> NetworkConnectionFailure {
        switch error {
        case .dns:
            return .dnsResolution
        case .tls:
            return .tlsHandshake
        case .wifiAware:
            return .networkUnavailable
        case let .posix(code):
            switch code {
            case .ECONNREFUSED:
                return .connectionRefused
            case .ECONNRESET, .EPIPE:
                return .connectionReset
            case .ENETDOWN, .ENETUNREACH, .EHOSTUNREACH:
                return .networkUnavailable
            default:
                return .unknown
            }
        @unknown default:
            return .unknown
        }
    }
}

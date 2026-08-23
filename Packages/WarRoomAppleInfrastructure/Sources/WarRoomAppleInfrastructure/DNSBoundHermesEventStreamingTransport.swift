import Darwin
import Foundation
import Network
import WarRoomCore
import WarRoomHermes

/// A redacted transport failure. Cases deliberately omit URLs, addresses,
/// headers, credentials, response bytes, and arbitrary underlying error text.
public enum DNSBoundHermesEventStreamingTransportError: Error, Equatable, Sendable {
    case unsupportedRequest
    case invalidRelativePath
    case invalidCredential
    case invalidRedirect
    case redirectLimitExceeded(limit: Int)
    case noApprovedPeer
    case invalidReceiveLimit
}

extension DNSBoundHermesEventStreamingTransportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedRequest:
            return "The streaming request is not an accepted GET request."
        case .invalidRelativePath:
            return "The streaming request path is invalid."
        case .invalidCredential:
            return "The provider credential is invalid."
        case .invalidRedirect:
            return "The provider redirect is invalid."
        case let .redirectLimitExceeded(limit):
            return "The provider exceeded the \(limit)-redirect limit."
        case .noApprovedPeer:
            return "No approved network peer is available."
        case .invalidReceiveLimit:
            return "The network receive limit is invalid."
        }
    }
}

/// One bounded receive result from an injected DNS-bound connection.
public struct DNSBoundHermesConnectionReceive: Equatable, Sendable {
    public let data: Data
    public let isComplete: Bool

    public init(data: Data, isComplete: Bool) {
        self.data = data
        self.isComplete = isComplete
    }
}

/// Minimal connection seam used to keep DNS and wire tests deterministic.
public protocol DNSBoundHermesConnection: Sendable {
    func start() async throws
    func send(_ data: Data) async throws
    func receive(maximumLength: Int) async throws -> DNSBoundHermesConnectionReceive
    func cancel()
}

/// Creates a connection only from a validated plan and a peer in its snapshot.
public protocol DNSBoundHermesConnectionCreating: Sendable {
    func makeConnection(
        plan: DNSBoundConnectionPlan,
        address: DNSBoundIPAddress
    ) throws -> any DNSBoundHermesConnection
}

/// Production adapter retaining the planner's numeric peer, logical-host SNI,
/// HTTP/1.1 ALPN, and default platform trust evaluation.
public struct NetworkFrameworkDNSBoundHermesConnectionFactory: DNSBoundHermesConnectionCreating, Sendable {
    public init() {}

    public func makeConnection(
        plan: DNSBoundConnectionPlan,
        address: DNSBoundIPAddress
    ) throws -> any DNSBoundHermesConnection {
        NetworkFrameworkDNSBoundHermesConnection(
            connection: try plan.makeConnection(to: address)
        )
    }
}

/// Opt-in Hermes SSE transport that binds every connection and accepted
/// redirect hop to a freshly validated DNS snapshot.
public struct DNSBoundHermesEventStreamingTransport: HermesEventStreamingTransport, Sendable {
    private let policy: HermesEventStreamingTransportPolicy
    private let limits: BoundedHTTP1Limits
    private let maximumRedirects: Int
    private let planner: DNSBoundConnectionPlanner
    private let connectionFactory: any DNSBoundHermesConnectionCreating

    public init(
        policy: HermesEventStreamingTransportPolicy = .secureDefault,
        httpLimits: BoundedHTTP1Limits = .secureDefault,
        maximumRedirects: Int = 3,
        resolver: any DNSBoundAddressResolving = SystemDNSBoundAddressResolver(),
        connectionFactory: any DNSBoundHermesConnectionCreating = NetworkFrameworkDNSBoundHermesConnectionFactory()
    ) throws {
        guard maximumRedirects >= 0, maximumRedirects <= 8 else {
            throw DNSBoundHermesEventStreamingTransportError.redirectLimitExceeded(limit: 8)
        }
        guard policy.maximumChunkBytes > 0 else {
            throw DNSBoundHermesEventStreamingTransportError.invalidReceiveLimit
        }
        self.policy = policy
        self.limits = try BoundedHTTP1Limits(
            maximumHeaderBytes: httpLimits.maximumHeaderBytes,
            maximumHeaderCount: httpLimits.maximumHeaderCount,
            maximumLineBytes: httpLimits.maximumLineBytes,
            maximumBodyBytes: httpLimits.maximumBodyBytes,
            maximumDeliveryBytes: min(httpLimits.maximumDeliveryBytes, policy.maximumChunkBytes)
        )
        self.maximumRedirects = maximumRedirects
        self.planner = DNSBoundConnectionPlanner(resolver: resolver)
        self.connectionFactory = connectionFactory
    }

    public func stream(
        _ request: ProviderRequest,
        to endpoint: ValidatedEndpoint,
        credential: ProviderCredential?
    ) async throws -> HermesProviderByteStream {
        try Task.checkCancellation()
        guard request.method == .get, request.body == nil else {
            throw DNSBoundHermesEventStreamingTransportError.unsupportedRequest
        }
        let destination = try Self.makeDestination(for: request, endpoint: endpoint)
        let cancellation = DNSBoundHermesCancellationController()
        let coordinator = try NetworkTerminalStateCoordinator<Int, Data>(
            bufferingLimit: policy.maximumBufferedChunks,
            cancelConnection: { cancellation.terminate() }
        )
        let bytes = try coordinator.takeStream()

        cancellation.replaceActivityTimeout(makeActivityTimeout(coordinator: coordinator))

        let resourceTimeout = Task {
            try? await Task.sleep(for: .seconds(policy.resourceTimeout))
            guard !Task.isCancelled else { return }
            coordinator.timeout()
        }
        cancellation.installResourceTimeout(resourceTimeout)

        let operation = Task {
            await run(
                request: request,
                initialDestination: destination,
                endpoint: endpoint,
                credential: credential,
                coordinator: coordinator,
                cancellation: cancellation
            )
        }
        cancellation.installOperation(operation)

        do {
            let statusCode = try await coordinator.awaitResponse()
            try Task.checkCancellation()
            return HermesProviderByteStream(statusCode: statusCode, bytes: bytes)
        } catch {
            coordinator.cancel()
            throw error
        }
    }

    private func run(
        request: ProviderRequest,
        initialDestination: URL,
        endpoint: ValidatedEndpoint,
        credential: ProviderCredential?,
        coordinator: NetworkTerminalStateCoordinator<Int, Data>,
        cancellation: DNSBoundHermesCancellationController
    ) async {
        do {
            var destination = initialDestination
            var redirectCount = 0
            let origin = Origin(endpoint.url)

            while true {
                try Task.checkCancellation()

                // This is intentionally repeated for every accepted redirect.
                // Exact-origin redirects share the endpoint's host, port, and
                // declared boundary, but never reuse its prior DNS snapshot.
                let plan = try await planner.plan(for: endpoint)
                try Task.checkCancellation()
                guard let address = plan.addresses.first else {
                    throw DNSBoundHermesEventStreamingTransportError.noApprovedPeer
                }

                // Credential conversion and request serialization happen only
                // after every resolved address has passed boundary validation.
                let wireRequest = try makeWireRequest(
                    destination: destination,
                    plan: plan,
                    credential: credential
                )
                let connection = try connectionFactory.makeConnection(
                    plan: plan,
                    address: address
                )
                cancellation.setCurrent(connection)
                try await connection.start()
                try Task.checkCancellation()
                try await connection.send(wireRequest)

                var parser = try BoundedHTTP1ResponseParser(requestMethod: "GET", limits: limits)
                var redirect: URL?
                var completed = false

                while !completed, redirect == nil {
                    try Task.checkCancellation()
                    let received = try await connection.receive(
                        maximumLength: policy.maximumChunkBytes
                    )
                    cancellation.replaceActivityTimeout(
                        makeActivityTimeout(coordinator: coordinator)
                    )
                    let events: [BoundedHTTP1ResponseEvent]
                    if received.isComplete {
                        var accumulated = try parser.receive(received.data)
                        accumulated.append(contentsOf: try parser.finishEOF())
                        events = accumulated
                    } else {
                        guard !received.data.isEmpty else {
                            throw BoundedHTTP1Error.unexpectedEndOfStream
                        }
                        events = try parser.receive(received.data)
                    }

                    for event in events {
                        switch event {
                        case .informational:
                            continue
                        case let .head(head):
                            if Self.isRedirect(head.statusCode) {
                                guard redirectCount < maximumRedirects else {
                                    throw DNSBoundHermesEventStreamingTransportError.redirectLimitExceeded(
                                        limit: maximumRedirects
                                    )
                                }
                                redirect = try Self.redirectDestination(
                                    from: head,
                                    relativeTo: destination,
                                    requiredOrigin: origin
                                )
                            } else {
                                _ = coordinator.publishResponse(head.statusCode)
                            }
                        case let .body(data):
                            guard redirect == nil else { continue }
                            if coordinator.receive(data) == .rejectedBufferOverflow {
                                return
                            }
                        case .complete:
                            completed = true
                        }
                    }

                    if received.isComplete { completed = true }
                }

                if let redirect {
                    cancellation.cancelCurrent()
                    destination = redirect
                    redirectCount += 1
                    continue
                }

                guard parser.isComplete || completed else {
                    throw BoundedHTTP1Error.unexpectedEndOfStream
                }
                coordinator.finish()
                return
            }
        } catch is CancellationError {
            coordinator.cancel()
        } catch {
            coordinator.fail(Self.mapFailure(error))
        }
    }

    private func makeActivityTimeout(
        coordinator: NetworkTerminalStateCoordinator<Int, Data>
    ) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(for: .seconds(policy.requestTimeout))
            guard !Task.isCancelled else { return }
            coordinator.timeout()
        }
    }

    private func makeWireRequest(
        destination: URL,
        plan: DNSBoundConnectionPlan,
        credential: ProviderCredential?
    ) throws -> Data {
        guard let components = URLComponents(url: destination, resolvingAgainstBaseURL: false) else {
            throw DNSBoundHermesEventStreamingTransportError.invalidRelativePath
        }
        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        let target = components.percentEncodedQuery.map { "\(path)?\($0)" } ?? path
        var headers = [
            BoundedHTTP1Header(name: "Host", value: Self.hostHeader(plan: plan)),
            BoundedHTTP1Header(name: "Accept", value: "text/event-stream"),
            BoundedHTTP1Header(name: "Connection", value: "close"),
        ]
        if let credential {
            headers.append(
                BoundedHTTP1Header(
                    name: "Authorization",
                    value: "Bearer \(try Self.bearerValue(from: credential))"
                )
            )
        }
        return try BoundedHTTP1RequestSerializer.serialize(
            BoundedHTTP1Request(method: "GET", target: target, headers: headers),
            limits: limits
        )
    }

    private static func makeDestination(
        for request: ProviderRequest,
        endpoint: ValidatedEndpoint
    ) throws -> URL {
        let decodedPath = request.relativePath.removingPercentEncoding ?? request.relativePath
        guard !decodedPath.split(separator: "/", omittingEmptySubsequences: false).contains(".."),
              !decodedPath.contains("\\"),
              !decodedPath.hasPrefix("//"),
              var components = URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false)
        else {
            throw DNSBoundHermesEventStreamingTransportError.invalidRelativePath
        }
        let basePath = components.percentEncodedPath.hasSuffix("/")
            ? String(components.percentEncodedPath.dropLast())
            : components.percentEncodedPath
        components.percentEncodedPath = basePath + request.relativePath
        components.queryItems = request.queryItems.isEmpty ? nil : request.queryItems.map {
            URLQueryItem(name: $0.name, value: $0.value)
        }
        components.fragment = nil
        guard let result = components.url, Origin(result) == Origin(endpoint.url) else {
            throw DNSBoundHermesEventStreamingTransportError.invalidRelativePath
        }
        return result
    }

    private static func bearerValue(from credential: ProviderCredential) throws -> String {
        let data = credential.withUnsafeBytes { Data($0) }
        guard !data.isEmpty,
              !data.contains(0x0A),
              !data.contains(0x0D),
              data.allSatisfy({ $0 >= 0x20 && $0 != 0x7F }),
              let value = String(data: data, encoding: .utf8)
        else {
            throw DNSBoundHermesEventStreamingTransportError.invalidCredential
        }
        return value
    }

    private static func hostHeader(plan: DNSBoundConnectionPlan) -> String {
        let host = plan.serverName.contains(":") ? "[\(plan.serverName)]" : plan.serverName
        return plan.port == 443 ? host : "\(host):\(plan.port)"
    }

    private static func isRedirect(_ statusCode: Int) -> Bool {
        [301, 302, 303, 307, 308].contains(statusCode)
    }

    private static func redirectDestination(
        from head: BoundedHTTP1ResponseHead,
        relativeTo current: URL,
        requiredOrigin: Origin
    ) throws -> URL {
        let locations = head.headers.filter {
            $0.name.caseInsensitiveCompare("location") == .orderedSame
        }
        let rawLocation = locations.first?.value ?? ""
        let decodedLocation = rawLocation.removingPercentEncoding ?? rawLocation
        guard locations.count == 1,
              !rawLocation.isEmpty,
              rawLocation == rawLocation.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawLocation.contains(where: { $0.isWhitespace }),
              !decodedLocation.contains("\\"),
              !decodedLocation.split(separator: "/", omittingEmptySubsequences: false).contains(".."),
              let resolved = URL(string: rawLocation, relativeTo: current)?.absoluteURL,
              resolved.user == nil,
              resolved.password == nil,
              resolved.fragment == nil,
              Origin(resolved) == requiredOrigin
        else {
            throw DNSBoundHermesEventStreamingTransportError.invalidRedirect
        }
        return resolved
    }

    private static func mapFailure(_ error: Error) -> NetworkTerminalError {
        if let terminal = error as? NetworkTerminalError { return terminal }
        if let connection = error as? NetworkConnectionFailure {
            return .connection(connection)
        }
        if let bounded = error as? BoundedHTTP1Error {
            switch bounded {
            case .invalidStatusLine:
                return .protocolFailure(.malformedStatusLine)
            case .invalidHeader, .malformedLineEnding, .lineTooLong,
                 .headersTooLarge, .tooManyHeaders:
                return .protocolFailure(.invalidHeader)
            case .bodyTooLarge:
                return .protocolFailure(.bodyLimitExceeded)
            case .unexpectedEndOfStream:
                return .protocolFailure(.unexpectedEndOfStream)
            default:
                return .protocolFailure(.unsupportedFraming)
            }
        }
        if let dns = error as? DNSBoundConnectionError {
            switch dns {
            case .resolutionFailed, .noResolvedAddresses:
                return .connection(.dnsResolution)
            default:
                return .protocolFailure(.unknown)
            }
        }
        return .protocolFailure(.unknown)
    }
}

private final class DNSBoundHermesCancellationController: @unchecked Sendable {
    private let lock = NSLock()
    private var current: (any DNSBoundHermesConnection)?
    private var operation: Task<Void, Never>?
    private var activityTimeout: Task<Void, Never>?
    private var resourceTimeout: Task<Void, Never>?
    private var terminated = false

    func setCurrent(_ connection: any DNSBoundHermesConnection) {
        let cancelImmediately = lock.withLock { () -> Bool in
            guard !terminated else { return true }
            current = connection
            return false
        }
        if cancelImmediately { connection.cancel() }
    }

    func cancelCurrent() {
        let connection = lock.withLock { () -> (any DNSBoundHermesConnection)? in
            defer { current = nil }
            return current
        }
        connection?.cancel()
    }

    func installOperation(_ task: Task<Void, Never>) {
        install(task, at: \Self.operation)
    }

    func replaceActivityTimeout(_ task: Task<Void, Never>) {
        let action = lock.withLock { () -> (Task<Void, Never>?, Bool) in
            guard !terminated else { return (nil, true) }
            let previous = activityTimeout
            activityTimeout = task
            return (previous, false)
        }
        action.0?.cancel()
        if action.1 { task.cancel() }
    }

    func installResourceTimeout(_ task: Task<Void, Never>) {
        install(task, at: \Self.resourceTimeout)
    }

    func terminate() {
        let resources = lock.withLock { () -> (
            (any DNSBoundHermesConnection)?,
            Task<Void, Never>?,
            Task<Void, Never>?,
            Task<Void, Never>?
        )? in
            guard !terminated else { return nil }
            terminated = true
            let result = (current, operation, activityTimeout, resourceTimeout)
            current = nil
            operation = nil
            activityTimeout = nil
            resourceTimeout = nil
            return result
        }
        resources?.0?.cancel()
        resources?.1?.cancel()
        resources?.2?.cancel()
        resources?.3?.cancel()
    }

    private func install(
        _ task: Task<Void, Never>,
        at keyPath: ReferenceWritableKeyPath<DNSBoundHermesCancellationController, Task<Void, Never>?>
    ) {
        let cancelImmediately = lock.withLock { () -> Bool in
            guard !terminated else { return true }
            self[keyPath: keyPath] = task
            return false
        }
        if cancelImmediately { task.cancel() }
    }
}

private final class NetworkFrameworkDNSBoundHermesConnection: DNSBoundHermesConnection, @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "ai.thox.warroom.hermes.dns-bound")
    private let lock = NSLock()
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var startResult: Result<Void, Error>?
    private var didStart = false
    private var didCancel = false

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let action = lock.withLock { () -> Result<Void, Error>? in
                    guard !didStart else {
                        return .failure(NetworkTerminalError.protocolFailure(.unknown))
                    }
                    didStart = true
                    if let startResult { return startResult }
                    startContinuation = continuation
                    connection.stateUpdateHandler = { [weak self] state in
                        self?.handle(state: state)
                    }
                    connection.start(queue: queue)
                    return nil
                }
                if let action { continuation.resume(with: action) }
            }
        } onCancel: {
            cancel()
        }
    }

    func send(_ data: Data) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: Self.map(error))
                    } else {
                        continuation.resume()
                    }
                })
            }
        } onCancel: {
            cancel()
        }
    }

    func receive(maximumLength: Int) async throws -> DNSBoundHermesConnectionReceive {
        guard maximumLength > 0 else {
            throw DNSBoundHermesEventStreamingTransportError.invalidReceiveLimit
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                connection.receive(
                    minimumIncompleteLength: 1,
                    maximumLength: maximumLength
                ) { data, _, isComplete, error in
                    if let error {
                        continuation.resume(throwing: Self.map(error))
                    } else {
                        continuation.resume(
                            returning: DNSBoundHermesConnectionReceive(
                                data: data ?? Data(),
                                isComplete: isComplete
                            )
                        )
                    }
                }
            }
        } onCancel: {
            cancel()
        }
    }

    func cancel() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            guard !didCancel else { return nil }
            didCancel = true
            if startResult == nil {
                startResult = .failure(NetworkTerminalError.cancelled)
            }
            defer { startContinuation = nil }
            return startContinuation
        }
        continuation?.resume(throwing: NetworkTerminalError.cancelled)
        connection.cancel()
    }

    private func handle(state: NWConnection.State) {
        let result: Result<Void, Error>?
        switch state {
        case .ready:
            result = .success(())
        case let .failed(error):
            result = .failure(Self.map(error))
        case .cancelled:
            result = .failure(NetworkTerminalError.cancelled)
        default:
            result = nil
        }
        guard let result else { return }
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            guard startResult == nil else { return nil }
            startResult = result
            defer { startContinuation = nil }
            return startContinuation
        }
        continuation?.resume(with: result)
    }

    private static func map(_ error: NWError) -> NetworkTerminalError {
        switch error {
        case .dns:
            return .connection(.dnsResolution)
        case .tls:
            return .connection(.tlsHandshake)
        case let .posix(code):
            switch code {
            case .ECONNREFUSED:
                return .connection(.connectionRefused)
            case .ECONNRESET, .EPIPE:
                return .connection(.connectionReset)
            case .ENETDOWN, .ENETUNREACH, .EHOSTUNREACH:
                return .connection(.networkUnavailable)
            default:
                return .connection(.unknown)
            }
        case .wifiAware:
            return .connection(.unknown)
        @unknown default:
            return .connection(.unknown)
        }
    }
}

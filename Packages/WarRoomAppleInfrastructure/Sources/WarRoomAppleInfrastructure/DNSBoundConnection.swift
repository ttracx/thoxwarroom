import Darwin
import Foundation
import Network
import Security
import WarRoomCore

/// The workspace-facing name for Core's explicit network boundary declaration.
public typealias WorkspaceBoundary = NetworkBoundary

/// The only address scopes that may be used for a workspace connection.
public enum DNSBoundAddressScope: String, Equatable, Sendable {
    case loopback
    case privateNetwork
    case global
}

/// A validated numeric IP address and its security-relevant scope.
public struct DNSBoundIPAddress: Equatable, Hashable, Sendable {
    /// The numeric literal suitable for an `NWEndpoint.Host`.
    public let literal: String
    /// The address family reported by the strict parser.
    public let family: Family
    /// The policy scope determined from the address bytes.
    public let scope: DNSBoundAddressScope

    public enum Family: String, Equatable, Hashable, Sendable {
        case ipv4
        case ipv6
    }

    private let bytes: [UInt8]

    /// Strictly parses and classifies one IPv4 or IPv6 literal.
    ///
    /// Unspecified, multicast, documentation, benchmarking, transition-only,
    /// and reserved address space fails closed instead of being treated as global.
    public init(parsing literal: String) throws {
        guard !literal.isEmpty,
              literal == literal.trimmingCharacters(in: .whitespacesAndNewlines),
              !literal.contains("%") else {
            throw DNSBoundConnectionError.invalidAddressLiteral
        }

        if literal.contains("."), !literal.contains(":"), !Self.isStrictIPv4Literal(literal) {
            throw DNSBoundConnectionError.invalidAddressLiteral
        }
        if let parsed = Self.parse(literal, family: AF_INET, byteCount: 4) {
            self.literal = parsed.canonical
            self.family = .ipv4
            self.bytes = parsed.bytes
            self.scope = try Self.classifyIPv4(parsed.bytes)
            return
        }
        if let parsed = Self.parse(literal, family: AF_INET6, byteCount: 16) {
            self.literal = parsed.canonical
            self.family = .ipv6
            self.bytes = parsed.bytes
            self.scope = try Self.classifyIPv6(parsed.bytes)
            return
        }
        throw DNSBoundConnectionError.invalidAddressLiteral
    }

    private static func isStrictIPv4Literal(_ literal: String) -> Bool {
        let components = literal.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4 else { return false }
        return components.allSatisfy { component in
            !component.isEmpty
                && component.allSatisfy(\.isNumber)
                && (component.count == 1 || component.first != "0")
                && component.count <= 3
                && (Int(component).map { (0...255).contains($0) } ?? false)
        }
    }

    private static func parse(
        _ literal: String,
        family: Int32,
        byteCount: Int
    ) -> (bytes: [UInt8], canonical: String)? {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let result = bytes.withUnsafeMutableBytes { storage in
            inet_pton(family, literal, storage.baseAddress)
        }
        guard result == 1 else { return nil }

        var output = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let rendered = bytes.withUnsafeBytes { storage in
            inet_ntop(family, storage.baseAddress, &output, socklen_t(output.count))
        }
        guard rendered != nil else { return nil }
        return (bytes, String(cString: output))
    }

    private static func classifyIPv4(_ bytes: [UInt8]) throws -> DNSBoundAddressScope {
        precondition(bytes.count == 4)
        let first = bytes[0]
        let second = bytes[1]

        if first == 127 { return .loopback }
        if first == 10
            || (first == 172 && (16...31).contains(second))
            || (first == 192 && second == 168)
            || (first == 169 && second == 254) {
            return .privateNetwork
        }

        let isUnspecifiedOrReserved = first == 0
            || (first == 100 && (64...127).contains(second))
            || (first == 192 && second == 0 && bytes[2] == 0)
            || (first == 192 && second == 88 && bytes[2] == 99)
            || (first == 198 && (18...19).contains(second))
            || first >= 224
        let isDocumentation = (first == 192 && second == 0 && bytes[2] == 2)
            || (first == 198 && second == 51 && bytes[2] == 100)
            || (first == 203 && second == 0 && bytes[2] == 113)
        guard !isUnspecifiedOrReserved, !isDocumentation else {
            throw DNSBoundConnectionError.disallowedAddress
        }
        return .global
    }

    private static func classifyIPv6(_ bytes: [UInt8]) throws -> DNSBoundAddressScope {
        precondition(bytes.count == 16)
        if bytes.dropLast().allSatisfy({ $0 == 0 }), bytes[15] == 1 {
            return .loopback
        }
        if bytes[0] & 0xFE == 0xFC { return .privateNetwork }
        if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 { return .privateNetwork }

        let isUnspecified = bytes.allSatisfy { $0 == 0 }
        let isMulticast = bytes[0] == 0xFF
        let isDocumentation = (bytes[0...3] == [0x20, 0x01, 0x0D, 0xB8])
            || (bytes[0] == 0x3F && bytes[1] == 0xFF && bytes[2] & 0xF0 == 0)
        let isBenchmarking = bytes[0...5] == [0x20, 0x01, 0x00, 0x02, 0, 0]
        // Transition mechanisms can tunnel traffic to an embedded IPv4 peer,
        // which would bypass the scope proved by inspecting only the IPv6
        // prefix. Fail closed for Teredo (2001::/32) and 6to4 (2002::/16).
        let isTeredo = bytes[0...3] == [0x20, 0x01, 0x00, 0x00]
        let isSixToFour = bytes[0] == 0x20 && bytes[1] == 0x02
        let isOrchid = bytes[0] == 0x20
            && bytes[1] == 0x01
            && ((bytes[2] == 0x00 && bytes[3] & 0xF0 == 0x10)
                || (bytes[2] == 0x00 && bytes[3] & 0xF0 == 0x20))
        let isGloballyRoutablePrefix = bytes[0] & 0xE0 == 0x20
        guard !isUnspecified,
              !isMulticast,
              !isDocumentation,
              !isBenchmarking,
              !isTeredo,
              !isSixToFour,
              !isOrchid,
              isGloballyRoutablePrefix else {
            throw DNSBoundConnectionError.disallowedAddress
        }
        return .global
    }
}

/// A DNS resolver seam that can be replaced with deterministic fixtures in tests.
public protocol DNSBoundAddressResolving: Sendable {
    /// Returns every numeric address currently resolved for a logical hostname.
    func resolve(hostname: String) async throws -> [String]
}

/// System `getaddrinfo` resolver used by the production connection planner.
public struct SystemDNSBoundAddressResolver: DNSBoundAddressResolving, Sendable {
    public init() {}

    public func resolve(hostname: String) async throws -> [String] {
        guard !hostname.isEmpty,
              hostname == hostname.trimmingCharacters(in: .whitespacesAndNewlines),
              !hostname.contains(where: { $0.isWhitespace }) else {
            throw DNSBoundConnectionError.invalidHostname
        }

        let completion = DNSBoundResolverCompletion()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard completion.install(continuation) else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    completion.resolve(Result {
                        try Self.resolveSynchronously(hostname: hostname)
                    })
                }
            }
        } onCancel: {
            completion.cancel()
        }
    }

    private static func resolveSynchronously(hostname: String) throws -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(hostname, nil, &hints, &result)
        guard status == 0 else {
            throw DNSBoundConnectionError.resolutionFailed(code: status)
        }
        defer { freeaddrinfo(result) }

        var addresses: [String] = []
        var seen = Set<String>()
        var cursor = result
        while let info = cursor?.pointee {
            defer { cursor = info.ai_next }
            guard info.ai_family == AF_INET || info.ai_family == AF_INET6,
                  let socketAddress = info.ai_addr else {
                continue
            }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let nameStatus = getnameinfo(
                socketAddress,
                info.ai_addrlen,
                &buffer,
                socklen_t(buffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard nameStatus == 0 else { continue }
            let address = String(cString: buffer)
            if seen.insert(address).inserted {
                addresses.append(address)
            }
        }
        guard !addresses.isEmpty else {
            throw DNSBoundConnectionError.noResolvedAddresses
        }
        return addresses
    }
}

/// Makes the blocking system resolver cancellation-aware from the async
/// caller's perspective. `getaddrinfo` may finish later on its worker thread,
/// but this gate resumes the checked continuation exactly once.
private final class DNSBoundResolverCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[String], Error>?
    private var cancelled = false

    func install(_ continuation: CheckedContinuation<[String], Error>) -> Bool {
        lock.withLock {
            guard !cancelled else { return false }
            self.continuation = continuation
            return true
        }
    }

    func resolve(_ result: Result<[String], Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<[String], Error>? in
            guard !cancelled else { return nil }
            cancelled = true
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(with: result)
    }

    func cancel() {
        let continuation = lock.withLock { () -> CheckedContinuation<[String], Error>? in
            guard !cancelled else { return nil }
            cancelled = true
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(throwing: CancellationError())
    }
}

/// Errors from resolution, boundary validation, or connection construction.
///
/// Cases intentionally omit hostnames and address literals so logging the error
/// cannot disclose private infrastructure metadata.
public enum DNSBoundConnectionError: Error, Equatable, Sendable {
    case invalidHostname
    case unsupportedScheme
    case invalidPort
    case resolutionFailed(code: Int32)
    case noResolvedAddresses
    case invalidAddressLiteral
    case disallowedAddress
    case mixedAddressScopes
    case boundaryMismatch(declared: WorkspaceBoundary, resolved: DNSBoundAddressScope)
    case addressNotInValidatedSet
}

/// A fully validated DNS snapshot bound to an endpoint's declared boundary.
public struct DNSBoundConnectionPlan: Sendable {
    /// The logical TLS identity retained for SNI and system trust evaluation.
    public let serverName: String
    /// The endpoint TCP port.
    public let port: UInt16
    /// All validated numeric peers returned by the resolver snapshot.
    public let addresses: [DNSBoundIPAddress]
    /// The sole ALPN protocol offered by this HTTP/1.1 primitive.
    public let applicationProtocols: [String]

    fileprivate init(serverName: String, port: UInt16, addresses: [DNSBoundIPAddress]) {
        self.serverName = serverName
        self.port = port
        self.addresses = addresses
        self.applicationProtocols = ["http/1.1"]
    }

    /// Creates a connection to one approved numeric peer.
    ///
    /// TLS uses the original logical hostname and the platform's default trust
    /// evaluation. No custom verification block is installed.
    public func makeConnection(to address: DNSBoundIPAddress) throws -> NWConnection {
        guard addresses.contains(address) else {
            throw DNSBoundConnectionError.addressNotInValidatedSet
        }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw DNSBoundConnectionError.invalidPort
        }
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(
            tls.securityProtocolOptions,
            serverName
        )
        sec_protocol_options_add_tls_application_protocol(
            tls.securityProtocolOptions,
            "http/1.1"
        )
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        return NWConnection(
            host: NWEndpoint.Host(address.literal),
            port: nwPort,
            using: parameters
        )
    }
}

/// Resolves and validates every address before any connection can be created.
public struct DNSBoundConnectionPlanner: Sendable {
    private let resolver: any DNSBoundAddressResolving

    public init(resolver: any DNSBoundAddressResolving = SystemDNSBoundAddressResolver()) {
        self.resolver = resolver
    }

    public func plan(for endpoint: ValidatedEndpoint) async throws -> DNSBoundConnectionPlan {
        guard endpoint.url.scheme?.lowercased() == "https" else {
            throw DNSBoundConnectionError.unsupportedScheme
        }
        guard let hostname = endpoint.url.host,
              !hostname.isEmpty,
              hostname == hostname.trimmingCharacters(in: .whitespacesAndNewlines),
              !hostname.contains(where: { $0.isWhitespace }) else {
            throw DNSBoundConnectionError.invalidHostname
        }
        let effectivePort = endpoint.url.port ?? 443
        guard let port = UInt16(exactly: effectivePort), port > 0 else {
            throw DNSBoundConnectionError.invalidPort
        }

        let literals = try await resolver.resolve(hostname: hostname)
        guard !literals.isEmpty else {
            throw DNSBoundConnectionError.noResolvedAddresses
        }
        let addresses = try literals.map(DNSBoundIPAddress.init(parsing:))
        let scopes = Set(addresses.map(\.scope))
        guard scopes.count == 1, let resolvedScope = scopes.first else {
            throw DNSBoundConnectionError.mixedAddressScopes
        }
        let requiredScope: DNSBoundAddressScope
        switch endpoint.boundary {
        case .localMachine:
            requiredScope = .loopback
        case .privateNetwork:
            requiredScope = .privateNetwork
        case .hosted:
            requiredScope = .global
        }
        guard resolvedScope == requiredScope else {
            throw DNSBoundConnectionError.boundaryMismatch(
                declared: endpoint.boundary,
                resolved: resolvedScope
            )
        }
        return DNSBoundConnectionPlan(
            serverName: hostname,
            port: port,
            addresses: addresses
        )
    }
}

import Foundation

/// The user-controlled network boundary containing a workspace provider.
public enum NetworkBoundary: String, Codable, CaseIterable, Sendable {
    /// A service reachable only through the current device's loopback interface.
    case localMachine
    /// A service addressed through a private network or private DNS name.
    case privateNetwork
    /// A service addressed through a public DNS name or public IP address.
    case hosted
}

/// An explicit grant permitting a workspace to use a hosted provider.
public enum HostedAccessAuthorization: String, Codable, Sendable {
    /// Hosted provider access has not been authorized.
    case denied
    /// The user explicitly authorized hosted provider access.
    case granted
}

/// Policy applied when validating a workspace provider endpoint.
public struct EndpointValidationPolicy: Equatable, Sendable {
    /// Explicit TCP ports accepted for HTTP endpoints.
    public let allowedHTTPPorts: Set<Int>
    /// Explicit TCP ports accepted for HTTPS endpoints.
    public let allowedHTTPSPorts: Set<Int>
    /// Whether unencrypted HTTP is allowed for private-network endpoints.
    public let allowsPrivateNetworkHTTP: Bool
    /// DNS suffixes treated as private network names.
    public let privateDNSSuffixes: Set<String>

    /// Creates an endpoint policy. Omitted ports still use their scheme's default port.
    public init(
        allowedHTTPPorts: Set<Int> = [80],
        allowedHTTPSPorts: Set<Int> = [443],
        allowsPrivateNetworkHTTP: Bool = false,
        privateDNSSuffixes: Set<String> = [".home.arpa", ".internal", ".lan", ".local"]
    ) {
        self.allowedHTTPPorts = allowedHTTPPorts
        self.allowedHTTPSPorts = allowedHTTPSPorts
        self.allowsPrivateNetworkHTTP = allowsPrivateNetworkHTTP
        self.privateDNSSuffixes = Set(privateDNSSuffixes.map { $0.lowercased() })
    }

    /// Conservative defaults: HTTPS on 443, loopback HTTP on 80, and no private HTTP.
    public static let secureDefault = EndpointValidationPolicy()
}

/// A reason that an endpoint cannot be used by a workspace.
public enum EndpointValidationError: Error, Equatable, Sendable {
    case emptyEndpoint
    case containsWhitespace
    case malformedURL
    case unsupportedScheme
    case missingHost
    case invalidHost
    case embeddedCredentials
    case queryNotAllowed
    case fragmentNotAllowed
    case pathTraversal
    case invalidPort
    case portNotAllowed(port: Int, scheme: String)
    case boundaryMismatch(declared: NetworkBoundary, detected: NetworkBoundary)
    case insecurePrivateNetworkTransport
    case insecureHostedTransport
    case hostedAccessNotAuthorized
}

/// A normalized provider base URL that has passed boundary and transport policy checks.
public struct ValidatedEndpoint: Equatable, Hashable, Codable, Sendable {
    /// The normalized base URL.
    public let url: URL
    /// The verified network boundary for the host.
    public let boundary: NetworkBoundary

    fileprivate init(url: URL, boundary: NetworkBoundary) {
        self.url = url
        self.boundary = boundary
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case boundary
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let encodedURL = try values.decode(URL.self, forKey: .url)
        let encodedBoundary = try values.decode(NetworkBoundary.self, forKey: .boundary)
        let decodedPort = encodedURL.port
        let policy = EndpointValidationPolicy(
            allowedHTTPPorts: decodedPort.map { [$0] } ?? [80],
            allowedHTTPSPorts: decodedPort.map { [$0] } ?? [443],
            allowsPrivateNetworkHTTP: true
        )
        self = try EndpointValidator.validate(
            encodedURL.absoluteString,
            declaredBoundary: encodedBoundary,
            hostedAccess: encodedBoundary == .hosted ? .granted : .denied,
            policy: policy
        )
    }
}

/// Validates provider endpoints without performing DNS resolution or network access.
public enum EndpointValidator {
    /// Validates and normalizes a provider base URL under an explicit boundary declaration.
    public static func validate(
        _ rawEndpoint: String,
        declaredBoundary: NetworkBoundary,
        hostedAccess: HostedAccessAuthorization = .denied,
        policy: EndpointValidationPolicy = .secureDefault
    ) throws -> ValidatedEndpoint {
        guard !rawEndpoint.isEmpty else {
            throw EndpointValidationError.emptyEndpoint
        }
        guard rawEndpoint == rawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawEndpoint.contains(where: { $0.isWhitespace }) else {
            throw EndpointValidationError.containsWhitespace
        }
        guard var components = URLComponents(string: rawEndpoint),
              components.url != nil else {
            throw EndpointValidationError.malformedURL
        }

        let scheme = components.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else {
            throw EndpointValidationError.unsupportedScheme
        }
        guard components.user == nil, components.password == nil else {
            throw EndpointValidationError.embeddedCredentials
        }
        guard components.query == nil else {
            throw EndpointValidationError.queryNotAllowed
        }
        guard components.fragment == nil else {
            throw EndpointValidationError.fragmentNotAllowed
        }
        guard let rawHost = components.host, !rawHost.isEmpty else {
            throw EndpointValidationError.missingHost
        }

        let host = rawHost
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()
        guard isValidHost(host) else {
            throw EndpointValidationError.invalidHost
        }
        guard !containsPathTraversal(components.percentEncodedPath) else {
            throw EndpointValidationError.pathTraversal
        }

        let detectedBoundary = try detectBoundary(
            host: host,
            privateDNSSuffixes: policy.privateDNSSuffixes
        )
        guard detectedBoundary == declaredBoundary else {
            throw EndpointValidationError.boundaryMismatch(
                declared: declaredBoundary,
                detected: detectedBoundary
            )
        }
        if declaredBoundary == .hosted && hostedAccess != .granted {
            throw EndpointValidationError.hostedAccessNotAuthorized
        }
        if declaredBoundary == .hosted && scheme != "https" {
            throw EndpointValidationError.insecureHostedTransport
        }
        if declaredBoundary == .privateNetwork,
           scheme == "http",
           !policy.allowsPrivateNetworkHTTP {
            throw EndpointValidationError.insecurePrivateNetworkTransport
        }

        if let port = components.port {
            guard (1...65_535).contains(port) else {
                throw EndpointValidationError.invalidPort
            }
            let allowedPorts = scheme == "https" ? policy.allowedHTTPSPorts : policy.allowedHTTPPorts
            guard allowedPorts.contains(port) else {
                throw EndpointValidationError.portNotAllowed(port: port, scheme: scheme!)
            }
        } else if hasMalformedExplicitPort(rawEndpoint, components: components) {
            throw EndpointValidationError.invalidPort
        }

        components.scheme = scheme
        if !host.contains(":") {
            components.host = host
        }
        components.path = normalizedPath(components.percentEncodedPath)
        guard let normalizedURL = components.url else {
            throw EndpointValidationError.malformedURL
        }
        return ValidatedEndpoint(url: normalizedURL, boundary: detectedBoundary)
    }

    private static func detectBoundary(
        host: String,
        privateDNSSuffixes: Set<String>
    ) throws -> NetworkBoundary {
        if host == "localhost" || host.hasSuffix(".localhost") {
            return .localMachine
        }
        if let octets = ipv4Octets(host) {
            if octets[0] == 127 {
                return .localMachine
            }
            if octets[0] == 10
                || (octets[0] == 172 && (16...31).contains(octets[1]))
                || (octets[0] == 192 && octets[1] == 168)
                || (octets[0] == 169 && octets[1] == 254) {
                return .privateNetwork
            }
            return .hosted
        }
        if host.allSatisfy({ $0.isNumber || $0 == "." }) {
            throw EndpointValidationError.invalidHost
        }
        if host == "::1" {
            return .localMachine
        }
        if host.contains(":") {
            let compact = host.replacingOccurrences(of: ":", with: "")
            if compact.hasPrefix("fc") || compact.hasPrefix("fd")
                || compact.hasPrefix("fe8") || compact.hasPrefix("fe9")
                || compact.hasPrefix("fea") || compact.hasPrefix("feb") {
                return .privateNetwork
            }
            return .hosted
        }
        if !host.contains(".") || privateDNSSuffixes.contains(where: host.hasSuffix) {
            return .privateNetwork
        }
        return .hosted
    }

    private static func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { part -> Int? in
            guard !part.isEmpty,
                  part.allSatisfy(\.isNumber),
                  (part.count == 1 || part.first != "0"),
                  let value = Int(part),
                  (0...255).contains(value) else {
                return nil
            }
            return value
        }
        return octets.count == 4 ? octets : nil
    }

    private static func isValidHost(_ host: String) -> Bool {
        guard host.unicodeScalars.allSatisfy({ $0.isASCII }) else { return false }
        if host.contains(":") {
            return host.allSatisfy { $0.isHexDigit || $0 == ":" || $0 == "." }
        }
        guard host.count <= 253,
              host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else {
            return false
        }
        return host.split(separator: ".").allSatisfy { label in
            !label.isEmpty
                && label.count <= 63
                && label.first != "-"
                && label.last != "-"
        }
    }

    private static func containsPathTraversal(_ path: String) -> Bool {
        let decoded = path.removingPercentEncoding ?? path
        return decoded.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    private static func normalizedPath(_ path: String) -> String {
        if path.isEmpty || path == "/" { return "" }
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private static func hasMalformedExplicitPort(
        _ rawEndpoint: String,
        components: URLComponents
    ) -> Bool {
        guard let authorityStart = rawEndpoint.range(of: "://")?.upperBound else { return true }
        let authority = rawEndpoint[authorityStart...].prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        if authority.hasPrefix("[") {
            guard let bracket = authority.firstIndex(of: "]") else { return true }
            let suffix = authority[authority.index(after: bracket)...]
            return !suffix.isEmpty && (suffix.first != ":" || suffix.dropFirst().isEmpty)
        }
        let colonCount = authority.filter { $0 == ":" }.count
        return colonCount > 0 && components.port == nil
    }
}

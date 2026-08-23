import Foundation

/// Persistence boundary for workspace profiles. No concrete storage is provided in WR-002.
public protocol WorkspaceProfileStore: Sendable {
    func profiles() async throws -> [WorkspaceProfile]
    func profile(id: WorkspaceID) async throws -> WorkspaceProfile?
    func save(_ profile: WorkspaceProfile) async throws
    func deleteProfile(id: WorkspaceID) async throws
}

/// An opaque credential payload whose description never reveals its value.
public struct ProviderCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    fileprivate let bytes: Data

    public init(bytes: Data) {
        self.bytes = bytes
    }

    public var description: String { "<redacted>" }
    public var debugDescription: String { "ProviderCredential(<redacted>)" }

    /// Grants temporary read access without exposing the credential through descriptions.
    public func withUnsafeBytes<Result>(
        _ body: (UnsafeRawBufferPointer) throws -> Result
    ) rethrows -> Result {
        try bytes.withUnsafeBytes(body)
    }
}

/// Secret-storage boundary. A Keychain implementation belongs to a later security slice.
public protocol CredentialVault: Sendable {
    func credential(for workspaceID: WorkspaceID) async throws -> ProviderCredential?
    func store(_ credential: ProviderCredential, for workspaceID: WorkspaceID) async throws
    func deleteCredential(for workspaceID: WorkspaceID) async throws
}

/// A provider request containing only relative routing data and an optional body.
public struct ProviderRequest: Equatable, Sendable {
    public enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case delete = "DELETE"
    }

    public let method: Method
    public let relativePath: String
    /// Validated non-secret query items. Credentials and sensitive content must never use this field.
    public let queryItems: [ProviderQueryItem]
    public let body: Data?

    public init(
        method: Method,
        relativePath: String,
        queryItems: [ProviderQueryItem] = [],
        body: Data? = nil
    ) throws {
        let decodedPath = relativePath.removingPercentEncoding ?? relativePath
        guard relativePath.hasPrefix("/"),
              !relativePath.hasPrefix("//"),
              !relativePath.contains("\\"),
              !decodedPath.contains("\\"),
              !decodedPath.hasPrefix("//"),
              !decodedPath.dropFirst().contains("//"),
              !decodedPath.split(separator: "/", omittingEmptySubsequences: false).contains(".."),
              !relativePath.contains("?") && !relativePath.contains("#") else {
            throw ProviderRequestError.invalidRelativePath
        }
        guard queryItems.count <= 16,
              Set(queryItems.map(\.name)).count == queryItems.count else {
            throw ProviderRequestError.invalidQueryItems
        }
        self.method = method
        self.relativePath = relativePath
        self.queryItems = queryItems
        self.body = body
    }
}

/// A bounded RFC 3986 unreserved query item intended only for routing and filtering.
public struct ProviderQueryItem: Equatable, Hashable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) throws {
        guard (1...64).contains(name.utf8.count),
              (1...512).contains(value.utf8.count),
              Self.isUnreserved(name),
              Self.isUnreserved(value) else {
            throw ProviderQueryItemError.invalidComponent
        }
        self.name = name
        self.value = value
    }

    private static func isUnreserved(_ value: String) -> Bool {
        value.utf8.allSatisfy { byte in
            (byte >= 65 && byte <= 90)
                || (byte >= 97 && byte <= 122)
                || (byte >= 48 && byte <= 57)
                || byte == 45 || byte == 46 || byte == 95 || byte == 126
        }
    }
}

public enum ProviderQueryItemError: Error, Equatable, Sendable {
    case invalidComponent
}

/// A reason that a provider request cannot be constructed.
public enum ProviderRequestError: Error, Equatable, Sendable {
    case invalidRelativePath
    case invalidQueryItems
}

/// A transport-neutral provider response.
public struct ProviderResponse: Equatable, Sendable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

/// Network execution seam. WR-002 intentionally provides no implementation.
public protocol ProviderTransport: Sendable {
    func send(
        _ request: ProviderRequest,
        to endpoint: ValidatedEndpoint,
        credential: ProviderCredential?
    ) async throws -> ProviderResponse
}

/// Sink for already-redacted audit events. WR-002 intentionally provides no persistence.
public protocol AuditEventRecording: Sendable {
    func record(_ event: AuditEvent) async throws
}

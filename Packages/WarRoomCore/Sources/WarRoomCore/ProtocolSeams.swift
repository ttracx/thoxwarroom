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
    public let body: Data?

    public init(method: Method, relativePath: String, body: Data? = nil) throws {
        guard relativePath.hasPrefix("/"),
              !relativePath.hasPrefix("//"),
              !relativePath.split(separator: "/").contains(".."),
              !relativePath.contains("?") && !relativePath.contains("#") else {
            throw ProviderRequestError.invalidRelativePath
        }
        self.method = method
        self.relativePath = relativePath
        self.body = body
    }
}

/// A reason that a provider request cannot be constructed.
public enum ProviderRequestError: Error, Equatable, Sendable {
    case invalidRelativePath
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

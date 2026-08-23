import Foundation

/// Stable identity for an isolated workspace.
public struct WorkspaceID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    /// Creates a new random workspace identity.
    public static func make() -> WorkspaceID {
        WorkspaceID(rawValue: UUID())
    }
}

/// Stable identity for a provider implementation.
public struct ProviderID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// A capability a provider can truthfully advertise to the application.
public enum ProviderCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case modelCatalog
    case chatCompletions
    case streamingChat
    case sourceCitations
    case hermesSessions
    case scopedApprovals
    case warRoomStatus
}

/// Static provider metadata used for capability-gated product surfaces.
public struct ProviderDescriptor: Equatable, Codable, Sendable {
    public let id: ProviderID
    public let displayName: String
    public let capabilities: Set<ProviderCapability>

    public init(
        id: ProviderID,
        displayName: String,
        capabilities: Set<ProviderCapability>
    ) {
        self.id = id
        self.displayName = displayName
        self.capabilities = capabilities
    }

    /// Returns whether this provider advertises a capability.
    public func supports(_ capability: ProviderCapability) -> Bool {
        capabilities.contains(capability)
    }
}

/// A validated, isolated workspace configuration without credentials.
public struct WorkspaceProfile: Identifiable, Equatable, Codable, Sendable {
    public let id: WorkspaceID
    public let displayName: String
    public let endpoint: ValidatedEndpoint
    public let provider: ProviderDescriptor
    public let createdAt: Date
    public let updatedAt: Date

    /// Creates a profile after validating its user-visible name.
    public init(
        id: WorkspaceID = .make(),
        displayName: String,
        endpoint: ValidatedEndpoint,
        provider: ProviderDescriptor,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) throws {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw WorkspaceProfileError.emptyDisplayName
        }
        guard normalizedName.count <= 80 else {
            throw WorkspaceProfileError.displayNameTooLong
        }
        guard updatedAt >= createdAt else {
            throw WorkspaceProfileError.updatedBeforeCreation
        }
        self.id = id
        self.displayName = normalizedName
        self.endpoint = endpoint
        self.provider = provider
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A reason that a workspace profile cannot be created.
public enum WorkspaceProfileError: Error, Equatable, Sendable {
    case emptyDisplayName
    case displayNameTooLong
    case updatedBeforeCreation
}

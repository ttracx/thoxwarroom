import Foundation

/// Durable, non-sensitive progress markers for credential-first workspace deletion.
public enum WorkspaceDeletionStage: String, Codable, CaseIterable, Sendable {
    /// Provider credentials must be erased before workspace encryption keys or ciphertext.
    case credentialDeletionPending
    /// Workspace encryption keys and remaining ciphertext must be erased.
    case encryptedWorkspaceDeletionPending
    /// Local selectors and legacy metadata must be cleared.
    case selectorCleanupPending
}

/// The single resumable deletion intent supported by the current single-workspace lifecycle.
public struct WorkspaceDeletionJournalEntry: Equatable, Codable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible {
    public static let schemaVersion: UInt16 = 1

    public let workspaceID: WorkspaceID
    public let stage: WorkspaceDeletionStage

    public init(workspaceID: WorkspaceID, stage: WorkspaceDeletionStage) {
        self.workspaceID = workspaceID
        self.stage = stage
    }

    public var description: String {
        "WorkspaceDeletionJournalEntry(stage: \(stage.rawValue), workspace: <redacted>)"
    }

    public var debugDescription: String { description }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case workspaceID
        case stage
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(UInt16.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: values,
                debugDescription: "Unsupported workspace deletion journal schema"
            )
        }
        workspaceID = try values.decode(WorkspaceID.self, forKey: .workspaceID)
        stage = try values.decode(WorkspaceDeletionStage.self, forKey: .stage)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(Self.schemaVersion, forKey: .schemaVersion)
        try values.encode(workspaceID, forKey: .workspaceID)
        try values.encode(stage, forKey: .stage)
    }
}

/// Encrypted durable storage for the current workspace deletion intent.
public protocol WorkspaceDeletionJournal: Sendable {
    /// Returns the pending intent, or `nil` when deletion is not in progress.
    func pendingEntry() async throws -> WorkspaceDeletionJournalEntry?

    /// Atomically creates or advances the pending deletion intent.
    func save(_ entry: WorkspaceDeletionJournalEntry) async throws

    /// Clears a completed intent. Clearing an absent journal is idempotent.
    func clear() async throws
}

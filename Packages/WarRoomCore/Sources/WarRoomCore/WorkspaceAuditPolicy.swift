import Foundation

/// A user-confirmed, workspace-scoped audit retention policy.
///
/// Absence of this value means that no retention policy has been configured. Callers
/// must never substitute `AuditRetentionPolicy.standard` for an absent record.
public struct ConfirmedWorkspaceAuditPolicy: Equatable, Codable, Sendable {
    public static let schemaVersion: UInt16 = 1

    public let workspaceID: WorkspaceID
    public let revision: UInt64
    public let retention: AuditRetentionPolicy
    public let confirmedAt: Date
    public let lastAppliedAt: Date?

    public init(
        workspaceID: WorkspaceID,
        revision: UInt64,
        retention: AuditRetentionPolicy,
        confirmedAt: Date,
        lastAppliedAt: Date? = nil
    ) throws {
        let canonicalConfirmedAt = try Self.canonicalDate(confirmedAt)
        let canonicalLastAppliedAt = try lastAppliedAt.map(Self.canonicalDate)
        guard revision > 0,
              canonicalLastAppliedAt.map({ $0 >= canonicalConfirmedAt }) ?? true else {
            throw WorkspaceAuditPolicyError.invalidPolicy
        }
        self.workspaceID = workspaceID
        self.revision = revision
        self.retention = retention
        self.confirmedAt = canonicalConfirmedAt
        self.lastAppliedAt = canonicalLastAppliedAt
    }

    public func recordingApplication(at date: Date) throws -> ConfirmedWorkspaceAuditPolicy {
        guard revision < UInt64.max,
              Self.isFinite(date),
              date >= confirmedAt,
              lastAppliedAt.map({ date >= $0 }) ?? true else {
            throw WorkspaceAuditPolicyError.invalidPolicy
        }
        return try ConfirmedWorkspaceAuditPolicy(
            workspaceID: workspaceID,
            revision: revision + 1,
            retention: retention,
            confirmedAt: confirmedAt,
            lastAppliedAt: date
        )
    }

    private static func isFinite(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }

    private static func canonicalDate(_ date: Date) throws -> Date {
        let milliseconds = date.timeIntervalSince1970 * 1_000
        guard isFinite(date),
              milliseconds > Double(Int64.min),
              milliseconds < Double(Int64.max) else {
            throw WorkspaceAuditPolicyError.invalidPolicy
        }
        return Date(
            timeIntervalSince1970: Double(Int64(milliseconds.rounded())) / 1_000
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case workspaceID
        case revision
        case retention
        case confirmedAt
        case lastAppliedAt
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(UInt16.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: values,
                debugDescription: "Unsupported workspace audit policy schema"
            )
        }
        do {
            try self.init(
                workspaceID: values.decode(WorkspaceID.self, forKey: .workspaceID),
                revision: values.decode(UInt64.self, forKey: .revision),
                retention: values.decode(AuditRetentionPolicy.self, forKey: .retention),
                confirmedAt: values.decode(Date.self, forKey: .confirmedAt),
                lastAppliedAt: values.decodeIfPresent(Date.self, forKey: .lastAppliedAt)
            )
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid workspace audit policy",
                    underlyingError: error
                )
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(Self.schemaVersion, forKey: .schemaVersion)
        try values.encode(workspaceID, forKey: .workspaceID)
        try values.encode(revision, forKey: .revision)
        try values.encode(retention, forKey: .retention)
        try values.encode(confirmedAt, forKey: .confirmedAt)
        try values.encodeIfPresent(lastAppliedAt, forKey: .lastAppliedAt)
    }
}

/// Compare-and-swap persistence boundary for explicit audit policies.
public protocol WorkspaceAuditPolicyPersisting: Sendable {
    func policy(for workspaceID: WorkspaceID) async throws -> ConfirmedWorkspaceAuditPolicy?

    /// Saves exactly the next policy revision.
    ///
    /// `replacingRevision == nil` means the caller expects no existing policy.
    func save(
        _ policy: ConfirmedWorkspaceAuditPolicy,
        replacingRevision: UInt64?
    ) async throws
}

public enum WorkspaceAuditPolicyError: Error, Equatable, Sendable {
    case invalidPolicy
    case invalidLifecycleResult
    case revisionOverflow
}

/// Result of an explicit lifecycle application attempt.
public enum WorkspaceAuditPolicyApplication: Equatable, Sendable {
    /// No confirmed policy exists. No retention operation was invoked.
    case notConfigured
    /// The confirmed policy was applied and the application timestamp was persisted.
    case applied(AuditRetentionResult, ConfirmedWorkspaceAuditPolicy)
}

/// App-facing contract for confirming and applying workspace audit policy.
public protocol WorkspaceAuditLifecycleCoordinating: Sendable {
    func policy(for workspaceID: WorkspaceID) async throws -> ConfirmedWorkspaceAuditPolicy?

    func confirm(
        _ retention: AuditRetentionPolicy,
        for workspaceID: WorkspaceID,
        confirmedAt: Date
    ) async throws -> ConfirmedWorkspaceAuditPolicy

    func applyConfirmedPolicy(
        for workspaceID: WorkspaceID,
        asOf: Date
    ) async throws -> WorkspaceAuditPolicyApplication

    func exportSnapshot(
        _ request: AuditExportRequest,
        generatedAt: Date
    ) async throws -> RedactedAuditExportSnapshot
}

/// Serializes in-app policy changes and refuses to prune without a persisted,
/// explicitly confirmed policy.
public actor WorkspaceAuditLifecycleCoordinator: WorkspaceAuditLifecycleCoordinating {
    private let policyStore: any WorkspaceAuditPolicyPersisting
    private let lifecycle: any AuditLifecycleManaging

    public init(
        policyStore: any WorkspaceAuditPolicyPersisting,
        lifecycle: any AuditLifecycleManaging
    ) {
        self.policyStore = policyStore
        self.lifecycle = lifecycle
    }

    public func policy(for workspaceID: WorkspaceID) async throws
        -> ConfirmedWorkspaceAuditPolicy? {
        try await policyStore.policy(for: workspaceID)
    }

    public func confirm(
        _ retention: AuditRetentionPolicy,
        for workspaceID: WorkspaceID,
        confirmedAt: Date
    ) async throws -> ConfirmedWorkspaceAuditPolicy {
        let existing = try await policyStore.policy(for: workspaceID)
        guard existing?.revision != UInt64.max else {
            throw WorkspaceAuditPolicyError.revisionOverflow
        }
        let next = try ConfirmedWorkspaceAuditPolicy(
            workspaceID: workspaceID,
            revision: (existing?.revision ?? 0) + 1,
            retention: retention,
            confirmedAt: confirmedAt
        )
        guard existing.map({ next.confirmedAt >= $0.confirmedAt }) ?? true,
              existing?.lastAppliedAt.map({ next.confirmedAt >= $0 }) ?? true else {
            throw WorkspaceAuditPolicyError.invalidPolicy
        }
        try await policyStore.save(next, replacingRevision: existing?.revision)
        return next
    }

    public func applyConfirmedPolicy(
        for workspaceID: WorkspaceID,
        asOf: Date
    ) async throws -> WorkspaceAuditPolicyApplication {
        guard let confirmed = try await policyStore.policy(for: workspaceID) else {
            return .notConfigured
        }
        // Validate the application timeline before invoking the destructive
        // lifecycle boundary. Invalid or backdated requests must have no effect.
        let applied = try confirmed.recordingApplication(at: asOf)
        let result = try await lifecycle.applyRetention(
            confirmed.retention,
            to: workspaceID,
            asOf: asOf
        )
        guard result.workspaceID == workspaceID,
              result.policy == confirmed.retention else {
            throw WorkspaceAuditPolicyError.invalidLifecycleResult
        }
        try await policyStore.save(applied, replacingRevision: confirmed.revision)
        return .applied(result, applied)
    }

    public func exportSnapshot(
        _ request: AuditExportRequest,
        generatedAt: Date
    ) async throws -> RedactedAuditExportSnapshot {
        try await lifecycle.exportSnapshot(request, generatedAt: generatedAt)
    }
}

import Foundation

/// Caller-supplied, non-secret identity for exactly one mutating operation attempt.
public struct AuditedOperationCorrelationID: RawRepresentable, Hashable, Codable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue.uuidString.lowercased() }
    public var debugDescription: String {
        "AuditedOperationCorrelationID(\(description))"
    }
}

/// Result of atomically claiming a correlation ID and durably appending its intent.
public enum AuditedOperationIntentAppendResult: Equatable, Sendable {
    /// This correlation ID was new and the intent is durable.
    case appended
    /// This correlation ID was already claimed; callers must not execute the operation.
    case replayRejected
}

/// Terminal-state filter for crash reconciliation of audited operations.
public enum AuditedOperationReconciliationStatus: String, Codable, Sendable {
    case pending
    case terminal
}

/// Bounded result count for one workspace-scoped reconciliation query.
public struct AuditedOperationReconciliationLimit: Equatable, Hashable, Sendable {
    public static let maximum = 500
    public static let standard = AuditedOperationReconciliationLimit(validatedRawValue: 100)

    public let rawValue: Int

    public init(rawValue: Int) throws {
        guard (1...Self.maximum).contains(rawValue) else {
            throw AuditedOperationPersistenceError.invalidReconciliationLimit(rawValue)
        }
        self.rawValue = rawValue
    }

    private init(validatedRawValue: Int) {
        rawValue = validatedRawValue
    }
}

/// Explicitly workspace-scoped request for pending or terminal operation evidence.
public struct AuditedOperationReconciliationQuery: Equatable, Sendable {
    public let workspaceID: WorkspaceID
    public let status: AuditedOperationReconciliationStatus
    public let limit: AuditedOperationReconciliationLimit

    public init(
        workspaceID: WorkspaceID,
        status: AuditedOperationReconciliationStatus,
        limit: AuditedOperationReconciliationLimit = .standard
    ) {
        self.workspaceID = workspaceID
        self.status = status
        self.limit = limit
    }
}

/// Durable, already-redacted evidence for one claimed operation correlation ID.
public struct AuditedOperationReconciliationRecord: Equatable, Sendable {
    public let workspaceID: WorkspaceID
    public let correlationID: AuditedOperationCorrelationID
    public let intent: PersistableAuditEvent
    public let outcome: PersistableAuditEvent?

    public var status: AuditedOperationReconciliationStatus {
        outcome == nil ? .pending : .terminal
    }

    public init(
        workspaceID: WorkspaceID,
        correlationID: AuditedOperationCorrelationID,
        intent: PersistableAuditEvent,
        outcome: PersistableAuditEvent?
    ) throws {
        guard intent.event.workspaceID == workspaceID,
              outcome?.event.workspaceID == workspaceID || outcome == nil else {
            throw AuditedOperationPersistenceError.crossWorkspaceRecord
        }
        let expectedCorrelation = RedactedAuditValue.string(correlationID.description)
        guard intent.event.metadata["correlation_id"] == expectedCorrelation,
              outcome?.event.metadata["correlation_id"] == expectedCorrelation || outcome == nil else {
            throw AuditedOperationPersistenceError.invalidCorrelationEvidence
        }
        self.workspaceID = workspaceID
        self.correlationID = correlationID
        self.intent = intent
        self.outcome = outcome
    }
}

/// Bounded reconciliation result for exactly one workspace and lifecycle state.
public struct AuditedOperationReconciliationPage: Equatable, Sendable {
    public let workspaceID: WorkspaceID
    public let status: AuditedOperationReconciliationStatus
    public let records: [AuditedOperationReconciliationRecord]
    public let truncated: Bool

    public init(
        workspaceID: WorkspaceID,
        status: AuditedOperationReconciliationStatus,
        records: [AuditedOperationReconciliationRecord],
        truncated: Bool
    ) throws {
        guard records.count <= AuditedOperationReconciliationLimit.maximum else {
            throw AuditedOperationPersistenceError.reconciliationPageTooLarge
        }
        guard records.allSatisfy({
            $0.workspaceID == workspaceID && $0.status == status
        }) else {
            throw AuditedOperationPersistenceError.invalidReconciliationPage
        }
        self.workspaceID = workspaceID
        self.status = status
        self.records = records
        self.truncated = truncated
    }
}

/// Typed failures at the durable operation evidence boundary.
public enum AuditedOperationPersistenceError: Error, Equatable, Sendable {
    case invalidReconciliationLimit(Int)
    case crossWorkspaceRecord
    case invalidCorrelationEvidence
    case reconciliationPageTooLarge
    case invalidReconciliationPage
    case reconciliationUnavailable
}

/// Durable audit boundary for one-shot mutating operations.
///
/// Implementations must atomically claim `correlationID` and append `intent`.
/// Correlation IDs must be unique within the implementation's durable domain.
/// Reuse with any workspace or operation scope is a replay. Claims survive process
/// restarts and are never released, including after failure or cancellation.
public protocol DurableAuditedOperationStore: Sendable {
    func appendIntent(
        _ intent: PersistableAuditEvent,
        correlationID: AuditedOperationCorrelationID
    ) async throws -> AuditedOperationIntentAppendResult

    /// Appends the terminal outcome for a previously claimed correlation ID.
    /// Implementations must reject missing claims, cross-workspace outcomes, and
    /// second terminal outcomes rather than silently replacing durable evidence.
    func appendOutcome(
        _ outcome: PersistableAuditEvent,
        correlationID: AuditedOperationCorrelationID
    ) async throws

    /// Returns bounded pending or terminal evidence for one workspace after a crash.
    func reconciliationRecords(
        matching query: AuditedOperationReconciliationQuery
    ) async throws -> AuditedOperationReconciliationPage
}

public extension DurableAuditedOperationStore {
    /// Keeps append-only conformers source-compatible while failing closed when
    /// reconciliation has not yet been implemented by their persistence backend.
    func reconciliationRecords(
        matching query: AuditedOperationReconciliationQuery
    ) async throws -> AuditedOperationReconciliationPage {
        _ = query
        throw AuditedOperationPersistenceError.reconciliationUnavailable
    }
}

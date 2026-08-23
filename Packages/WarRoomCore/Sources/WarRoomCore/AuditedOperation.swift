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
}

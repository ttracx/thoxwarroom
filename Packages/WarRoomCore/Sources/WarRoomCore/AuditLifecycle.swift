import Foundation

/// Validated finite audit retention duration measured in 24-hour days.
public struct AuditRetentionDays: Equatable, Hashable, Codable, Sendable {
    public static let minimum = 30
    public static let maximum = 2_555
    public static let standard = AuditRetentionDays(validatedRawValue: 365)

    public let rawValue: Int

    public init(rawValue: Int) throws {
        guard (Self.minimum...Self.maximum).contains(rawValue) else {
            throw AuditLifecycleError.invalidRetentionDays(rawValue)
        }
        self.rawValue = rawValue
    }

    private init(validatedRawValue: Int) {
        rawValue = validatedRawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(rawValue: container.decode(Int.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid audit retention duration"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Explicit audit retention choice. Indefinite retention is never implied by a sentinel value.
public enum AuditRetentionPolicy: Equatable, Codable, Sendable {
    case finite(AuditRetentionDays)
    case indefinite

    public static let standard = AuditRetentionPolicy.finite(.standard)
}

/// Result of one integrity-checked retention transaction.
public struct AuditRetentionResult: Equatable, Sendable {
    public let workspaceID: WorkspaceID
    public let policy: AuditRetentionPolicy
    public let cutoff: Date?
    public let priorRetainedEventCount: Int
    public let retainedEventCount: Int
    public let prunedEventCount: Int
    public let lifetimeEventCount: UInt64

    public init(
        workspaceID: WorkspaceID,
        policy: AuditRetentionPolicy,
        cutoff: Date?,
        priorRetainedEventCount: Int,
        retainedEventCount: Int,
        prunedEventCount: Int,
        lifetimeEventCount: UInt64
    ) throws {
        guard priorRetainedEventCount >= 0,
              retainedEventCount >= 0,
              prunedEventCount >= 0,
              retainedEventCount + prunedEventCount == priorRetainedEventCount,
              UInt64(retainedEventCount) <= lifetimeEventCount,
              (policy == .indefinite) == (cutoff == nil) else {
            throw AuditLifecycleError.invalidRetentionResult
        }
        self.workspaceID = workspaceID
        self.policy = policy
        self.cutoff = cutoff
        self.priorRetainedEventCount = priorRetainedEventCount
        self.retainedEventCount = retainedEventCount
        self.prunedEventCount = prunedEventCount
        self.lifetimeEventCount = lifetimeEventCount
    }
}

/// Bounded maximum number of events in one in-memory audit export.
public struct AuditExportLimit: Equatable, Hashable, Codable, Sendable {
    public static let maximum = 500
    public static let standard = AuditExportLimit(validatedRawValue: 100)
    public let rawValue: Int

    public init(rawValue: Int) throws {
        guard (1...Self.maximum).contains(rawValue) else {
            throw AuditLifecycleError.invalidExportLimit(rawValue)
        }
        self.rawValue = rawValue
    }

    private init(validatedRawValue: Int) {
        rawValue = validatedRawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(rawValue: container.decode(Int.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid audit export limit"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Metadata required to produce one bounded redacted export snapshot.
public struct AuditExportRequest: Equatable, Sendable {
    public let workspaceID: WorkspaceID
    public let occurredOnOrAfter: Date?
    public let occurredBefore: Date?
    public let applicationVersion: String
    public let limit: AuditExportLimit

    public init(
        workspaceID: WorkspaceID,
        occurredOnOrAfter: Date? = nil,
        occurredBefore: Date? = nil,
        applicationVersion: String,
        limit: AuditExportLimit = .standard
    ) throws {
        if let lower = occurredOnOrAfter, let upper = occurredBefore, lower >= upper {
            throw AuditLifecycleError.invalidExportTimeRange
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+-")
        guard (1...64).contains(applicationVersion.utf8.count),
              applicationVersion.unicodeScalars.allSatisfy(allowed.contains) else {
            throw AuditLifecycleError.invalidApplicationVersion
        }
        self.workspaceID = workspaceID
        self.occurredOnOrAfter = occurredOnOrAfter
        self.occurredBefore = occurredBefore
        self.applicationVersion = applicationVersion
        self.limit = limit
    }
}

/// One export-safe event. String metadata values are irreversibly redacted.
public struct RedactedAuditExportEvent: Equatable, Codable, Sendable {
    public let sourceSequence: UInt64
    public let id: AuditEventID
    public let occurredAt: Date
    public let category: String
    public let action: String
    public let outcome: AuditOutcome
    public let metadata: [String: RedactedAuditValue]

    public init(
        sourceSequence: UInt64,
        id: AuditEventID,
        occurredAt: Date,
        category: String,
        action: String,
        outcome: AuditOutcome,
        metadata: [String: RedactedAuditValue]
    ) {
        self.sourceSequence = sourceSequence
        self.id = id
        self.occurredAt = occurredAt
        self.category = category
        self.action = action
        self.outcome = outcome
        self.metadata = metadata
    }
}

/// Source-ledger commitment included with a redacted export.
public struct AuditExportIntegrity: Equatable, Codable, Sendable {
    public let ledgerGeneration: UInt64
    public let retainedEventCount: Int
    public let lifetimeEventCount: UInt64
    public let sourceHeadSHA256: String
    public let snapshotSHA256: String

    public init(
        ledgerGeneration: UInt64,
        retainedEventCount: Int,
        lifetimeEventCount: UInt64,
        sourceHeadSHA256: String,
        snapshotSHA256: String
    ) throws {
        guard retainedEventCount >= 0,
              UInt64(retainedEventCount) <= lifetimeEventCount,
              Self.isSHA256(sourceHeadSHA256),
              Self.isSHA256(snapshotSHA256) else {
            throw AuditLifecycleError.invalidExportIntegrity
        }
        self.ledgerGeneration = ledgerGeneration
        self.retainedEventCount = retainedEventCount
        self.lifetimeEventCount = lifetimeEventCount
        self.sourceHeadSHA256 = sourceHeadSHA256
        self.snapshotSHA256 = snapshotSHA256
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}

/// Versioned, bounded, in-memory redacted audit export.
public struct RedactedAuditExportSnapshot: Equatable, Codable, Sendable {
    public static let schemaVersion = 1
    public static let maximumEncodedBytes = 8 * 1_024 * 1_024

    public let schemaVersion: Int
    public let generatedAt: Date
    public let workspaceID: WorkspaceID
    public let occurredOnOrAfter: Date?
    public let occurredBefore: Date?
    public let applicationVersion: String
    public let events: [RedactedAuditExportEvent]
    public let truncated: Bool
    public let integrity: AuditExportIntegrity

    public init(
        generatedAt: Date,
        workspaceID: WorkspaceID,
        occurredOnOrAfter: Date?,
        occurredBefore: Date?,
        applicationVersion: String,
        events: [RedactedAuditExportEvent],
        truncated: Bool,
        integrity: AuditExportIntegrity
    ) throws {
        let allowedVersionCharacters = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+-"
        )
        guard events.count <= AuditExportLimit.maximum,
              events.allSatisfy({ $0.sourceSequence < integrity.lifetimeEventCount }),
              zip(events, events.dropFirst()).allSatisfy({ $0.sourceSequence < $1.sourceSequence }),
              (1...64).contains(applicationVersion.utf8.count),
              applicationVersion.unicodeScalars.allSatisfy(allowedVersionCharacters.contains),
              Self.validRange(lower: occurredOnOrAfter, upper: occurredBefore) else {
            throw AuditLifecycleError.invalidExportSnapshot
        }
        schemaVersion = Self.schemaVersion
        self.generatedAt = generatedAt
        self.workspaceID = workspaceID
        self.occurredOnOrAfter = occurredOnOrAfter
        self.occurredBefore = occurredBefore
        self.applicationVersion = applicationVersion
        self.events = events
        self.truncated = truncated
        self.integrity = integrity
    }

    private static func validRange(lower: Date?, upper: Date?) -> Bool {
        guard let lower, let upper else { return true }
        return lower < upper
    }
}

public enum AuditLifecycleError: Error, Equatable, Sendable {
    case invalidRetentionDays(Int)
    case invalidRetentionResult
    case invalidExportLimit(Int)
    case invalidExportTimeRange
    case invalidApplicationVersion
    case invalidExportIntegrity
    case invalidExportSnapshot
    case exportTooLarge(limit: Int)
}

/// Local audit lifecycle boundary implemented by encrypted platform persistence.
public protocol AuditLifecycleManaging: Sendable {
    func applyRetention(
        _ policy: AuditRetentionPolicy,
        to workspaceID: WorkspaceID,
        asOf: Date
    ) async throws -> AuditRetentionResult

    func exportSnapshot(
        _ request: AuditExportRequest,
        generatedAt: Date
    ) async throws -> RedactedAuditExportSnapshot
}

import Foundation

/// A redacted audit event validated for bounded durable persistence.
public struct PersistableAuditEvent: Equatable, Codable, Sendable {
    /// Maximum encoded event accepted by the persistence boundary: 64 KiB.
    public static let maximumEncodedBytes = 64 * 1_024
    /// Maximum metadata fields accepted by the persistence boundary.
    public static let maximumMetadataFields = 64

    public let event: AuditEvent

    /// Validates that an already-redacted event is bounded and safe to persist.
    public init(event: AuditEvent) throws {
        guard (1...64).contains(event.category.utf8.count),
              (1...64).contains(event.action.utf8.count) else {
            throw AuditPersistenceError.invalidEventName
        }
        guard event.metadata.count <= Self.maximumMetadataFields,
              event.metadata.allSatisfy({ key, value in
                  let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                  guard normalizedKey == key,
                        (1...64).contains(key.utf8.count) else { return false }
                  if case .string(let string) = value {
                      return string.utf8.count <= 256
                  }
                  return true
              }) else {
            throw AuditPersistenceError.metadataTooLarge
        }
        guard event.metadata.allSatisfy({ key, value in
            !AuditRedactor.isSensitiveKey(key) || value == .redacted
        }) else {
            throw AuditPersistenceError.metadataNotRedacted
        }
        let encoded = try JSONEncoder().encode(event)
        guard encoded.count <= Self.maximumEncodedBytes else {
            throw AuditPersistenceError.eventTooLarge(
                limit: Self.maximumEncodedBytes,
                actual: encoded.count
            )
        }
        self.event = event
    }

    private enum CodingKeys: String, CodingKey {
        case event
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(event: values.decode(AuditEvent.self, forKey: .event))
        } catch let error as AuditPersistenceError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid persistable audit event", underlyingError: error)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(event, forKey: .event)
    }
}

/// Opaque continuation supplied by an audit persistence implementation.
public struct AuditEventCursor: Equatable, Hashable, Codable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible {
    public static let maximumBytes = 512
    private let value: Data

    public init(value: Data) throws {
        guard (1...Self.maximumBytes).contains(value.count) else {
            throw AuditPersistenceError.invalidCursor
        }
        self.value = value
    }

    public var description: String { "<redacted-audit-cursor>" }
    public var debugDescription: String { "AuditEventCursor(<redacted>)" }

    /// Grants temporary read access for persistence implementations without changing redacted descriptions.
    public func withUnsafeBytes<Result>(
        _ body: (UnsafeRawBufferPointer) throws -> Result
    ) rethrows -> Result {
        try value.withUnsafeBytes(body)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(value: container.decode(Data.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid audit cursor"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// Bounded page size for durable audit reads.
public struct AuditEventPageLimit: Equatable, Hashable, Sendable {
    public static let maximum = 500
    public let rawValue: Int

    public init(rawValue: Int) throws {
        guard (1...Self.maximum).contains(rawValue) else {
            throw AuditPersistenceError.invalidPageLimit(rawValue)
        }
        self.rawValue = rawValue
    }

    public static let standard = AuditEventPageLimit(validatedRawValue: 100)

    private init(validatedRawValue: Int) {
        rawValue = validatedRawValue
    }
}

/// Explicitly workspace-scoped audit query.
public struct AuditEventQuery: Equatable, Sendable {
    public let workspaceID: WorkspaceID
    public let occurredOnOrAfter: Date?
    public let occurredBefore: Date?
    public let after: AuditEventCursor?
    public let limit: AuditEventPageLimit

    public init(
        workspaceID: WorkspaceID,
        occurredOnOrAfter: Date? = nil,
        occurredBefore: Date? = nil,
        after: AuditEventCursor? = nil,
        limit: AuditEventPageLimit = .standard
    ) throws {
        if let lowerBound = occurredOnOrAfter,
           let upperBound = occurredBefore,
           lowerBound >= upperBound {
            throw AuditPersistenceError.invalidTimeRange
        }
        self.workspaceID = workspaceID
        self.occurredOnOrAfter = occurredOnOrAfter
        self.occurredBefore = occurredBefore
        self.after = after
        self.limit = limit
    }
}

/// One validated page from a workspace-scoped durable audit query.
public struct AuditEventPage: Equatable, Sendable {
    public let workspaceID: WorkspaceID
    public let events: [PersistableAuditEvent]
    public let nextCursor: AuditEventCursor?

    public init(
        workspaceID: WorkspaceID,
        events: [PersistableAuditEvent],
        nextCursor: AuditEventCursor? = nil
    ) throws {
        guard events.count <= AuditEventPageLimit.maximum else {
            throw AuditPersistenceError.pageTooLarge
        }
        guard events.allSatisfy({ $0.event.workspaceID == workspaceID }) else {
            throw AuditPersistenceError.crossWorkspaceEvent
        }
        self.workspaceID = workspaceID
        self.events = events
        self.nextCursor = nextCursor
    }
}

/// Durable, ordered persistence boundary for already-redacted audit events.
public protocol DurableAuditEventStore: Sendable {
    /// Durably appends one event before returning success.
    func append(_ event: PersistableAuditEvent) async throws

    /// Returns an ordered, bounded page scoped to exactly one workspace.
    func events(matching query: AuditEventQuery) async throws -> AuditEventPage
}

/// Invalid audit persistence input rejected before storage.
public enum AuditPersistenceError: Error, Equatable, Sendable {
    case invalidEventName
    case metadataTooLarge
    case metadataNotRedacted
    case eventTooLarge(limit: Int, actual: Int)
    case invalidCursor
    case invalidPageLimit(Int)
    case invalidTimeRange
    case pageTooLarge
    case crossWorkspaceEvent
}

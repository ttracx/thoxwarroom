import Foundation

/// Stable identity for one audit event.
public struct AuditEventID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// Outcome of an auditable action.
public enum AuditOutcome: String, Codable, Sendable {
    case succeeded
    case denied
    case failed
    case cancelled
}

/// Privacy classification applied before audit metadata is retained.
public enum AuditPrivacy: String, Codable, Sendable {
    case nonSensitive
    case sensitive
}

/// A typed value proposed for audit metadata.
public enum AuditValue: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case boolean(Bool)
}

/// An audit metadata field that must be privacy-classified at the call site.
public struct AuditField: Equatable, Sendable {
    public let key: String
    public let value: AuditValue
    public let privacy: AuditPrivacy

    public init(key: String, value: AuditValue, privacy: AuditPrivacy) {
        self.key = key
        self.value = value
        self.privacy = privacy
    }
}

/// A value safe to serialize to the redacted audit stream.
public enum RedactedAuditValue: Equatable, Codable, Sendable {
    case string(String)
    case integer(Int)
    case boolean(Bool)
    case redacted

    private enum CodingKeys: String, CodingKey {
        case type
        case string
        case integer
        case boolean
    }

    private enum Kind: String, Codable {
        case string
        case integer
        case boolean
        case redacted
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .type) {
        case .string:
            self = .string(try values.decode(String.self, forKey: .string))
        case .integer:
            self = .integer(try values.decode(Int.self, forKey: .integer))
        case .boolean:
            self = .boolean(try values.decode(Bool.self, forKey: .boolean))
        case .redacted:
            self = .redacted
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .string(value):
            try values.encode(Kind.string, forKey: .type)
            try values.encode(value, forKey: .string)
        case let .integer(value):
            try values.encode(Kind.integer, forKey: .type)
            try values.encode(value, forKey: .integer)
        case let .boolean(value):
            try values.encode(Kind.boolean, forKey: .type)
            try values.encode(value, forKey: .boolean)
        case .redacted:
            try values.encode(Kind.redacted, forKey: .type)
        }
    }
}

/// A fully redacted audit event safe for persistence by a later storage slice.
public struct AuditEvent: Equatable, Codable, Sendable {
    public let id: AuditEventID
    public let occurredAt: Date
    public let workspaceID: WorkspaceID
    public let category: String
    public let action: String
    public let outcome: AuditOutcome
    public let metadata: [String: RedactedAuditValue]

    /// Creates an event and irreversibly redacts sensitive metadata values.
    public init(
        id: AuditEventID = AuditEventID(rawValue: UUID()),
        occurredAt: Date = Date(),
        workspaceID: WorkspaceID,
        category: String,
        action: String,
        outcome: AuditOutcome,
        fields: [AuditField] = []
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.workspaceID = workspaceID
        self.category = category
        self.action = action
        self.outcome = outcome
        self.metadata = AuditRedactor.redact(fields)
    }
}

/// Removes sensitive values before audit events cross a persistence seam.
public enum AuditRedactor {
    private static let sensitiveKeyFragments = [
        "authorization", "cookie", "credential", "document", "embedding",
        "password", "prompt", "secret", "token",
    ]

    /// Produces metadata containing no field marked sensitive or named like a secret.
    public static func redact(_ fields: [AuditField]) -> [String: RedactedAuditValue] {
        fields.reduce(into: [:]) { result, field in
            let normalizedKey = field.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty else { return }
            let keyIsSensitive = sensitiveKeyFragments.contains {
                normalizedKey.localizedCaseInsensitiveContains($0)
            }
            if field.privacy == .sensitive || keyIsSensitive {
                result[normalizedKey] = .redacted
                return
            }
            switch field.value {
            case let .string(value):
                result[normalizedKey] = .string(String(value.prefix(256)))
            case let .integer(value):
                result[normalizedKey] = .integer(value)
            case let .boolean(value):
                result[normalizedKey] = .boolean(value)
            }
        }
    }
}

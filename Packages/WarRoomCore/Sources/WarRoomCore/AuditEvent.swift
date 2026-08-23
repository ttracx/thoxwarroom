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

    private enum CodingKeys: String, CodingKey {
        case id
        case occurredAt
        case workspaceID
        case category
        case action
        case outcome
        case metadata
    }

    /// Re-applies redaction when events cross an untrusted decoding boundary.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(AuditEventID.self, forKey: .id)
        occurredAt = try values.decode(Date.self, forKey: .occurredAt)
        workspaceID = try values.decode(WorkspaceID.self, forKey: .workspaceID)
        category = try values.decode(String.self, forKey: .category)
        action = try values.decode(String.self, forKey: .action)
        outcome = try values.decode(AuditOutcome.self, forKey: .outcome)
        metadata = AuditRedactor.redactDecoded(
            try values.decode([String: RedactedAuditValue].self, forKey: .metadata)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(occurredAt, forKey: .occurredAt)
        try values.encode(workspaceID, forKey: .workspaceID)
        try values.encode(category, forKey: .category)
        try values.encode(action, forKey: .action)
        try values.encode(outcome, forKey: .outcome)
        try values.encode(metadata, forKey: .metadata)
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
        var result: [String: RedactedAuditValue] = [:]
        var retainedKeys: [String: String] = [:]
        for field in fields {
            let normalizedKey = field.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty else { continue }
            let canonicalKey = normalizedKey.lowercased()
            if let retainedKey = retainedKeys[canonicalKey] {
                result[retainedKey] = .redacted
                continue
            }
            retainedKeys[canonicalKey] = normalizedKey
            if field.privacy == .sensitive || isSensitiveKey(normalizedKey) {
                result[normalizedKey] = .redacted
                continue
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
        return result
    }

    /// Returns whether an audit metadata key is reserved for redacted values.
    public static func isSensitiveKey(_ key: String) -> Bool {
        sensitiveKeyFragments.contains {
            key.localizedCaseInsensitiveContains($0)
        }
    }

    static func redactDecoded(
        _ metadata: [String: RedactedAuditValue]
    ) -> [String: RedactedAuditValue] {
        let fields = metadata.keys.sorted().map { key -> AuditField in
            let value = metadata[key] ?? .redacted
            switch value {
            case .string(let string):
                return AuditField(key: key, value: .string(string), privacy: .nonSensitive)
            case .integer(let integer):
                return AuditField(key: key, value: .integer(integer), privacy: .nonSensitive)
            case .boolean(let boolean):
                return AuditField(key: key, value: .boolean(boolean), privacy: .nonSensitive)
            case .redacted:
                return AuditField(key: key, value: .boolean(false), privacy: .sensitive)
            }
        }
        return redact(fields)
    }
}

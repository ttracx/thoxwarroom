import Foundation

/// Stable identity for one encrypted workspace record.
public struct EncryptedWorkspaceRecordID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// A validated, non-secret collection name used to partition encrypted records.
public struct WorkspaceDataCollection: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    /// Creates a collection from 1...64 lowercase ASCII routing characters.
    public init?(rawValue: String) {
        guard Self.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    /// Validates a collection name and returns a typed failure when invalid.
    public init(validating rawValue: String) throws {
        guard Self.isValid(rawValue) else {
            throw EncryptedWorkspaceDataError.invalidCollection
        }
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(validating: container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid encrypted workspace collection"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func isValid(_ value: String) -> Bool {
        (1...64).contains(value.utf8.count) && value.utf8.allSatisfy { byte in
            (byte >= 97 && byte <= 122)
                || (byte >= 48 && byte <= 57)
                || byte == 45 || byte == 46 || byte == 95
        }
    }
}

/// Supported authenticated-encryption format for a workspace record.
public enum WorkspaceEncryptionAlgorithm: String, Codable, Sendable {
    /// AES with a 256-bit key, 96-bit nonce, and 128-bit authentication tag.
    case aes256GCM
}

/// Opaque reference to key material held outside workspace data persistence.
public struct EncryptionKeyReference: Hashable, Codable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible {
    private let value: String

    /// Creates a bounded opaque key reference without loading key material.
    public init(_ value: String) throws {
        guard (1...128).contains(value.utf8.count),
              value.utf8.allSatisfy({ byte in
                  (byte >= 65 && byte <= 90)
                      || (byte >= 97 && byte <= 122)
                      || (byte >= 48 && byte <= 57)
                      || byte == 45 || byte == 46 || byte == 95
              }) else {
            throw EncryptedWorkspaceDataError.invalidKeyReference
        }
        self.value = value
    }

    public var description: String { "<redacted-key-reference>" }
    public var debugDescription: String { "EncryptionKeyReference(<redacted>)" }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid encryption key reference"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// Authenticated ciphertext and routing metadata for one isolated workspace record.
public struct EncryptedWorkspaceRecord: Equatable, Codable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible {
    /// Maximum ciphertext accepted by the shared persistence contract: 16 MiB.
    public static let maximumCiphertextBytes = 16 * 1_024 * 1_024
    /// Required AES-GCM nonce length.
    public static let nonceBytes = 12
    /// Required AES-GCM authentication-tag length.
    public static let authenticationTagBytes = 16

    public let id: EncryptedWorkspaceRecordID
    public let workspaceID: WorkspaceID
    public let collection: WorkspaceDataCollection
    public let algorithm: WorkspaceEncryptionAlgorithm
    public let keyReference: EncryptionKeyReference
    public let nonce: Data
    public let ciphertext: Data
    public let authenticationTag: Data
    public let createdAt: Date
    public let updatedAt: Date

    /// Creates a validated encrypted envelope. Plaintext and key bytes are never accepted.
    public init(
        id: EncryptedWorkspaceRecordID = EncryptedWorkspaceRecordID(rawValue: UUID()),
        workspaceID: WorkspaceID,
        collection: WorkspaceDataCollection,
        algorithm: WorkspaceEncryptionAlgorithm = .aes256GCM,
        keyReference: EncryptionKeyReference,
        nonce: Data,
        ciphertext: Data,
        authenticationTag: Data,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) throws {
        guard nonce.count == Self.nonceBytes else {
            throw EncryptedWorkspaceDataError.invalidNonceLength(actual: nonce.count)
        }
        guard !ciphertext.isEmpty else {
            throw EncryptedWorkspaceDataError.emptyCiphertext
        }
        guard ciphertext.count <= Self.maximumCiphertextBytes else {
            throw EncryptedWorkspaceDataError.ciphertextTooLarge(
                limit: Self.maximumCiphertextBytes,
                actual: ciphertext.count
            )
        }
        guard authenticationTag.count == Self.authenticationTagBytes else {
            throw EncryptedWorkspaceDataError.invalidAuthenticationTagLength(
                actual: authenticationTag.count
            )
        }
        guard updatedAt >= createdAt else {
            throw EncryptedWorkspaceDataError.updatedBeforeCreation
        }
        self.id = id
        self.workspaceID = workspaceID
        self.collection = collection
        self.algorithm = algorithm
        self.keyReference = keyReference
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.authenticationTag = authenticationTag
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var description: String { "EncryptedWorkspaceRecord(<redacted>)" }
    public var debugDescription: String { "EncryptedWorkspaceRecord(<redacted>)" }

    private enum CodingKeys: String, CodingKey {
        case id
        case workspaceID
        case collection
        case algorithm
        case keyReference
        case nonce
        case ciphertext
        case authenticationTag
        case createdAt
        case updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                id: values.decode(EncryptedWorkspaceRecordID.self, forKey: .id),
                workspaceID: values.decode(WorkspaceID.self, forKey: .workspaceID),
                collection: values.decode(WorkspaceDataCollection.self, forKey: .collection),
                algorithm: values.decode(WorkspaceEncryptionAlgorithm.self, forKey: .algorithm),
                keyReference: values.decode(EncryptionKeyReference.self, forKey: .keyReference),
                nonce: values.decode(Data.self, forKey: .nonce),
                ciphertext: values.decode(Data.self, forKey: .ciphertext),
                authenticationTag: values.decode(Data.self, forKey: .authenticationTag),
                createdAt: values.decode(Date.self, forKey: .createdAt),
                updatedAt: values.decode(Date.self, forKey: .updatedAt)
            )
        } catch let error as EncryptedWorkspaceDataError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid encrypted workspace record", underlyingError: error)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(workspaceID, forKey: .workspaceID)
        try values.encode(collection, forKey: .collection)
        try values.encode(algorithm, forKey: .algorithm)
        try values.encode(keyReference, forKey: .keyReference)
        try values.encode(nonce, forKey: .nonce)
        try values.encode(ciphertext, forKey: .ciphertext)
        try values.encode(authenticationTag, forKey: .authenticationTag)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
    }
}

/// Invalid encrypted-envelope input rejected before persistence.
public enum EncryptedWorkspaceDataError: Error, Equatable, Sendable {
    case invalidCollection
    case invalidKeyReference
    case invalidNonceLength(actual: Int)
    case emptyCiphertext
    case ciphertextTooLarge(limit: Int, actual: Int)
    case invalidAuthenticationTagLength(actual: Int)
    case updatedBeforeCreation
}

/// Workspace-scoped persistence boundary for ciphertext-only records.
public protocol EncryptedWorkspaceDataStore: Sendable {
    /// Returns a record only when it belongs to the requested workspace.
    func record(
        id: EncryptedWorkspaceRecordID,
        in workspaceID: WorkspaceID
    ) async throws -> EncryptedWorkspaceRecord?

    /// Returns bounded records from one workspace collection.
    func records(
        in workspaceID: WorkspaceID,
        collection: WorkspaceDataCollection,
        limit: WorkspaceDataPageLimit
    ) async throws -> [EncryptedWorkspaceRecord]

    /// Atomically inserts or replaces one ciphertext record.
    func save(_ record: EncryptedWorkspaceRecord) async throws

    /// Deletes only the named record within the explicit workspace scope.
    func deleteRecord(
        id: EncryptedWorkspaceRecordID,
        in workspaceID: WorkspaceID
    ) async throws
}

/// Bounded encrypted-record page size.
public struct WorkspaceDataPageLimit: Equatable, Hashable, Sendable {
    public static let maximum = 500
    public let rawValue: Int

    public init(rawValue: Int) throws {
        guard (1...Self.maximum).contains(rawValue) else {
            throw WorkspaceDataPageLimitError.outOfRange(rawValue)
        }
        self.rawValue = rawValue
    }

    public static let standard = WorkspaceDataPageLimit(validatedRawValue: 100)

    private init(validatedRawValue: Int) {
        rawValue = validatedRawValue
    }
}

/// Invalid encrypted-record page bound.
public enum WorkspaceDataPageLimitError: Error, Equatable, Sendable {
    case outOfRange(Int)
}

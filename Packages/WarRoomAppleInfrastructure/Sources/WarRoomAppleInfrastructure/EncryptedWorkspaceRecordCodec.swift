import CryptoKit
import Foundation
import WarRoomCore

/// Redacted failures from authenticated workspace encryption.
public enum EncryptedWorkspaceRecordCodecError: Error, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible {
    case plaintextEmpty
    case plaintextTooLarge(limit: Int, actual: Int)
    case masterKeyMissing
    case unexpectedKeyReference
    case invalidTimestamp
    case authenticationFailed
    case invalidEnvelope

    public var description: String { "Encrypted workspace data is unavailable." }
    public var debugDescription: String { "EncryptedWorkspaceRecordCodecError(<redacted>)" }
}

/// Encrypts workspace payloads with AES-256-GCM and context-derived purpose keys.
public struct EncryptedWorkspaceRecordCodec: Sendable {
    /// Matches the Core ciphertext bound before AES-GCM sealing.
    public static let maximumPlaintextBytes = EncryptedWorkspaceRecord.maximumCiphertextBytes

    private static let derivationSalt = Data("THOX-WR-HKDF-SHA256-V1".utf8)
    private static let keyReference = try! EncryptionKeyReference("workspace-master-v1")

    private let keyVault: any WorkspaceMasterKeyProviding

    /// Creates a codec backed by workspace-scoped Keychain master keys.
    public init() {
        keyVault = KeychainWorkspaceMasterKeyVault()
    }

    init(keyVault: any WorkspaceMasterKeyProviding) {
        self.keyVault = keyVault
    }

    /// Explicitly provisions the first master key for a workspace.
    ///
    /// Callers must prove that no ciphertext already exists for this workspace before
    /// invoking this method. Normal sealing never creates or replaces key material.
    public func provisionMasterKey(for workspaceID: WorkspaceID) async throws {
        guard try await keyVault.masterKey(for: workspaceID, createIfMissing: true) != nil else {
            throw EncryptedWorkspaceRecordCodecError.masterKeyMissing
        }
    }

    /// Encrypts one bounded payload, authenticating its workspace, collection, and record identity.
    public func seal(
        _ plaintext: Data,
        workspaceID: WorkspaceID,
        collection: WorkspaceDataCollection,
        recordID: EncryptedWorkspaceRecordID = EncryptedWorkspaceRecordID(rawValue: UUID()),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) async throws -> EncryptedWorkspaceRecord {
        guard !plaintext.isEmpty else {
            throw EncryptedWorkspaceRecordCodecError.plaintextEmpty
        }
        guard plaintext.count <= Self.maximumPlaintextBytes else {
            throw EncryptedWorkspaceRecordCodecError.plaintextTooLarge(
                limit: Self.maximumPlaintextBytes,
                actual: plaintext.count
            )
        }
        let canonicalCreatedAt = try canonicalDate(createdAt)
        let canonicalUpdatedAt = try canonicalDate(updatedAt)
        guard canonicalUpdatedAt >= canonicalCreatedAt else {
            throw EncryptedWorkspaceRecordCodecError.invalidTimestamp
        }
        guard let masterKey = try await keyVault.masterKey(for: workspaceID, createIfMissing: false) else {
            throw EncryptedWorkspaceRecordCodecError.masterKeyMissing
        }

        let context = authenticatedContext(
            workspaceID: workspaceID,
            collection: collection,
            recordID: recordID,
            createdAt: canonicalCreatedAt,
            updatedAt: canonicalUpdatedAt
        )
        let purposeKey = derivePurposeKey(masterKey: masterKey, context: context)
        let sealedBox = try AES.GCM.seal(plaintext, using: purposeKey, authenticating: context)

        return try EncryptedWorkspaceRecord(
            id: recordID,
            workspaceID: workspaceID,
            collection: collection,
            keyReference: Self.keyReference,
            nonce: Data(sealedBox.nonce),
            ciphertext: sealedBox.ciphertext,
            authenticationTag: sealedBox.tag,
            createdAt: canonicalCreatedAt,
            updatedAt: canonicalUpdatedAt
        )
    }

    /// Decrypts and authenticates one record without exposing key material in failures.
    public func open(_ record: EncryptedWorkspaceRecord) async throws -> Data {
        guard record.keyReference == Self.keyReference else {
            throw EncryptedWorkspaceRecordCodecError.unexpectedKeyReference
        }
        guard record.algorithm == .aes256GCM else {
            throw EncryptedWorkspaceRecordCodecError.invalidEnvelope
        }
        let canonicalCreatedAt = try canonicalDate(record.createdAt)
        let canonicalUpdatedAt = try canonicalDate(record.updatedAt)
        guard canonicalCreatedAt == record.createdAt,
              canonicalUpdatedAt == record.updatedAt,
              canonicalUpdatedAt >= canonicalCreatedAt else {
            throw EncryptedWorkspaceRecordCodecError.invalidTimestamp
        }
        guard let masterKey = try await keyVault.masterKey(
            for: record.workspaceID,
            createIfMissing: false
        ) else {
            throw EncryptedWorkspaceRecordCodecError.masterKeyMissing
        }

        let context = authenticatedContext(
            workspaceID: record.workspaceID,
            collection: record.collection,
            recordID: record.id,
            createdAt: canonicalCreatedAt,
            updatedAt: canonicalUpdatedAt
        )
        let purposeKey = derivePurposeKey(masterKey: masterKey, context: context)
        do {
            let nonce = try AES.GCM.Nonce(data: record.nonce)
            let sealedBox = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: record.ciphertext,
                tag: record.authenticationTag
            )
            return try AES.GCM.open(sealedBox, using: purposeKey, authenticating: context)
        } catch {
            throw EncryptedWorkspaceRecordCodecError.authenticationFailed
        }
    }

    /// Idempotently deletes a workspace master key, cryptographically erasing its records.
    public func deleteMasterKey(for workspaceID: WorkspaceID) async throws {
        try await keyVault.deleteMasterKey(for: workspaceID)
    }

    private func derivePurposeKey(masterKey: SymmetricKey, context: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            salt: Self.derivationSalt,
            info: context,
            outputByteCount: 32
        )
    }

    private func authenticatedContext(
        workspaceID: WorkspaceID,
        collection: WorkspaceDataCollection,
        recordID: EncryptedWorkspaceRecordID,
        createdAt: Date,
        updatedAt: Date
    ) -> Data {
        let fields = [
            "THOX-WR-AES256-GCM-V1",
            workspaceID.rawValue.uuidString.lowercased(),
            collection.rawValue,
            recordID.rawValue.uuidString.lowercased(),
            WorkspaceEncryptionAlgorithm.aes256GCM.rawValue,
            "workspace-master-v1",
            String(millisecondsSince1970(createdAt)),
            String(millisecondsSince1970(updatedAt)),
        ]
        var result = Data()
        for field in fields {
            let bytes = Data(field.utf8)
            var length = UInt32(bytes.count).bigEndian
            withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
            result.append(bytes)
        }
        return result
    }

    private func canonicalDate(_ date: Date) throws -> Date {
        let seconds = date.timeIntervalSince1970
        let milliseconds = seconds * 1_000
        guard milliseconds.isFinite,
              milliseconds > Double(Int64.min),
              milliseconds < Double(Int64.max) else {
            throw EncryptedWorkspaceRecordCodecError.invalidTimestamp
        }
        return Date(timeIntervalSince1970: Double(millisecondsSince1970(date)) / 1_000)
    }

    private func millisecondsSince1970(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }
}

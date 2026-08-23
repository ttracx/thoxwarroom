import CryptoKit
import Foundation
import WarRoomCore

/// Redacted failures from encrypted workspace audit-policy persistence.
public enum EncryptedWorkspaceAuditPolicyStoreError: Error, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible {
    case anchorUnavailable
    case conflictingRevision
    case corruptRecord
    case crossWorkspaceRecord
    case keyUnavailable
    case lockUnavailable
    case rollbackDetected
    case storageUnavailable

    public var description: String { "Encrypted audit policy is unavailable." }
    public var debugDescription: String {
        "EncryptedWorkspaceAuditPolicyStoreError(<redacted>)"
    }
}

/// Device-local encrypted persistence for explicitly confirmed audit policies.
///
/// The encrypted record is committed before its independent Keychain anchor. A
/// record exactly one revision ahead of the anchor is the only recoverable crash
/// state. Missing, older, divergent, or cross-workspace state fails closed. This
/// store never applies retention; callers must invoke the Core lifecycle contract
/// from an explicit user action.
public actor EncryptedWorkspaceAuditPolicyStore: WorkspaceAuditPolicyPersisting {
    static let schemaVersion = 1
    static let maximumEncodedPolicyBytes = 16 * 1_024
    static let collection = try! WorkspaceDataCollection(
        validating: "private.audit-policy.v1"
    )
    static let recordID = EncryptedWorkspaceRecordID(
        rawValue: UUID(uuidString: "A7D17000-1ED6-4D1F-AD17-000000000003")!
    )

    private let dataStore: any EncryptedWorkspaceDataStore
    private let codec: EncryptedWorkspaceRecordCodec
    private let anchorVault: any WorkspaceAuditPolicyAnchorProviding
    private let lockCoordinator: AuditWorkspaceLockCoordinator
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates a policy store in protected Application Support storage with
    /// independent, non-synchronizing device-only Keychain keys and anchors.
    public init() throws {
        let workspaceRoot = try EncryptedWorkspaceFileDataStore.defaultRootURL()
        let recordRoot = workspaceRoot.deletingLastPathComponent()
            .appendingPathComponent("audit-policies", isDirectory: true)
        dataStore = try EncryptedWorkspaceFileDataStore(
            rootURL: recordRoot,
            fileSystem: SystemAtomicWorkspaceFileSystem()
        )
        codec = EncryptedWorkspaceRecordCodec(keyVault: KeychainWorkspaceMasterKeyVault(
            service: "ai.thox.warroom.audit-policy-master-keys",
            keychain: SystemKeychainItemClient()
        ))
        anchorVault = KeychainWorkspaceAuditPolicyAnchorVault()
        lockCoordinator = try AuditWorkspaceLockCoordinator(
            rootURL: recordRoot.deletingLastPathComponent()
                .appendingPathComponent("audit-policy-locks", isDirectory: true)
        )
        encoder = Self.makeEncoder()
        decoder = Self.makeDecoder()
    }

    init(
        dataStore: any EncryptedWorkspaceDataStore,
        codec: EncryptedWorkspaceRecordCodec,
        anchorVault: any WorkspaceAuditPolicyAnchorProviding,
        lockCoordinator: AuditWorkspaceLockCoordinator = .processLocalForTesting()
    ) {
        self.dataStore = dataStore
        self.codec = codec
        self.anchorVault = anchorVault
        self.lockCoordinator = lockCoordinator
        encoder = Self.makeEncoder()
        decoder = Self.makeDecoder()
    }

    public func policy(for workspaceID: WorkspaceID) async throws
        -> ConfirmedWorkspaceAuditPolicy? {
        do {
            return try await lockCoordinator.withLock(for: workspaceID) { [self] in
                try await loadWhileLocked(for: workspaceID)?.policy
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as EncryptedWorkspaceAuditPolicyStoreError {
            throw error
        } catch {
            throw EncryptedWorkspaceAuditPolicyStoreError.lockUnavailable
        }
    }

    public func save(
        _ policy: ConfirmedWorkspaceAuditPolicy,
        replacingRevision: UInt64?
    ) async throws {
        do {
            try await lockCoordinator.withLock(for: policy.workspaceID) { [self] in
                try await saveWhileLocked(policy, replacingRevision: replacingRevision)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as EncryptedWorkspaceAuditPolicyStoreError {
            throw error
        } catch {
            throw EncryptedWorkspaceAuditPolicyStoreError.lockUnavailable
        }
    }

    private func saveWhileLocked(
        _ policy: ConfirmedWorkspaceAuditPolicy,
        replacingRevision: UInt64?
    ) async throws {
        try Task.checkCancellation()
        let existing = try await loadWhileLocked(for: policy.workspaceID)
        guard existing?.policy.revision == replacingRevision,
              replacingRevision != UInt64.max,
              policy.revision == (replacingRevision ?? 0) + 1 else {
            throw EncryptedWorkspaceAuditPolicyStoreError.conflictingRevision
        }

        let anchor: StoredWorkspaceAuditPolicyAnchor
        do {
            anchor = try await anchorVault.initializeEmptyAnchor(for: policy.workspaceID)
        } catch {
            throw EncryptedWorkspaceAuditPolicyStoreError.anchorUnavailable
        }
        guard anchor.revision == (replacingRevision ?? 0),
              existing.map({ anchor.policyDigest == $0.digest })
                ?? (anchor == .empty) else {
            throw EncryptedWorkspaceAuditPolicyStoreError.rollbackDetected
        }

        let envelope = StoredWorkspaceAuditPolicyEnvelope(
            schemaVersion: Self.schemaVersion,
            workspaceID: policy.workspaceID,
            predecessorRevision: anchor.revision,
            predecessorDigest: anchor.policyDigest,
            policy: policy
        )
        let plaintext = try encodeAndValidate(envelope)
        if existing == nil {
            do {
                try await codec.provisionMasterKey(for: policy.workspaceID)
            } catch {
                throw EncryptedWorkspaceAuditPolicyStoreError.keyUnavailable
            }
        }
        let timestamp = policy.lastAppliedAt ?? policy.confirmedAt
        let record: EncryptedWorkspaceRecord
        do {
            record = try await codec.seal(
                plaintext,
                workspaceID: policy.workspaceID,
                collection: Self.collection,
                recordID: Self.recordID,
                createdAt: existing?.record.createdAt ?? policy.confirmedAt,
                updatedAt: timestamp
            )
        } catch {
            throw mapCodecWriteError(error)
        }
        do {
            try await dataStore.save(record)
        } catch {
            throw EncryptedWorkspaceAuditPolicyStoreError.storageUnavailable
        }

        let digest = SHA256.hash(data: plaintext)
        let nextAnchor: StoredWorkspaceAuditPolicyAnchor
        do {
            nextAnchor = try .validated(
                revision: policy.revision,
                policyDigest: Data(digest)
            )
            try await anchorVault.store(nextAnchor, for: policy.workspaceID)
        } catch {
            // The authenticated record is now one revision ahead and is recoverable
            // on the next read after Keychain access is restored.
            throw EncryptedWorkspaceAuditPolicyStoreError.anchorUnavailable
        }
    }

    private func loadWhileLocked(for workspaceID: WorkspaceID) async throws
        -> LocatedWorkspaceAuditPolicy? {
        try Task.checkCancellation()
        let record: EncryptedWorkspaceRecord?
        do {
            record = try await dataStore.record(id: Self.recordID, in: workspaceID)
        } catch {
            throw EncryptedWorkspaceAuditPolicyStoreError.storageUnavailable
        }
        let anchor: StoredWorkspaceAuditPolicyAnchor?
        do {
            anchor = try await anchorVault.anchor(for: workspaceID)
        } catch {
            throw EncryptedWorkspaceAuditPolicyStoreError.anchorUnavailable
        }

        guard let record else {
            guard anchor == nil || anchor == .empty else {
                throw EncryptedWorkspaceAuditPolicyStoreError.rollbackDetected
            }
            return nil
        }
        guard record.workspaceID == workspaceID else {
            throw EncryptedWorkspaceAuditPolicyStoreError.crossWorkspaceRecord
        }
        guard record.collection == Self.collection, record.id == Self.recordID else {
            throw EncryptedWorkspaceAuditPolicyStoreError.corruptRecord
        }
        guard let anchor else {
            throw EncryptedWorkspaceAuditPolicyStoreError.rollbackDetected
        }

        let plaintext: Data
        do {
            plaintext = try await codec.open(record)
        } catch {
            throw mapCodecReadError(error)
        }
        guard plaintext.count <= Self.maximumEncodedPolicyBytes else {
            throw EncryptedWorkspaceAuditPolicyStoreError.corruptRecord
        }
        let envelope: StoredWorkspaceAuditPolicyEnvelope
        do {
            envelope = try decoder.decode(
                StoredWorkspaceAuditPolicyEnvelope.self,
                from: plaintext
            )
        } catch {
            throw EncryptedWorkspaceAuditPolicyStoreError.corruptRecord
        }
        try validate(envelope, for: workspaceID)
        let digest = Data(SHA256.hash(data: plaintext))

        if anchor.revision == envelope.policy.revision,
           anchor.policyDigest == digest {
            return LocatedWorkspaceAuditPolicy(
                record: record,
                policy: envelope.policy,
                digest: digest
            )
        }
        guard anchor.revision < UInt64.max,
              envelope.policy.revision == anchor.revision + 1,
              envelope.predecessorRevision == anchor.revision,
              envelope.predecessorDigest == anchor.policyDigest else {
            throw EncryptedWorkspaceAuditPolicyStoreError.rollbackDetected
        }
        do {
            let recovered = try StoredWorkspaceAuditPolicyAnchor.validated(
                revision: envelope.policy.revision,
                policyDigest: digest
            )
            try await anchorVault.store(recovered, for: workspaceID)
        } catch {
            throw EncryptedWorkspaceAuditPolicyStoreError.anchorUnavailable
        }
        return LocatedWorkspaceAuditPolicy(
            record: record,
            policy: envelope.policy,
            digest: digest
        )
    }

    private func validate(
        _ envelope: StoredWorkspaceAuditPolicyEnvelope,
        for workspaceID: WorkspaceID
    ) throws {
        guard envelope.schemaVersion == Self.schemaVersion,
              envelope.workspaceID == workspaceID,
              envelope.policy.workspaceID == workspaceID,
              envelope.policy.revision > 0,
              envelope.predecessorRevision == envelope.policy.revision - 1,
              envelope.predecessorDigest.count
                == StoredWorkspaceAuditPolicyAnchor.digestByteCount,
              envelope.predecessorRevision != 0
                || envelope.predecessorDigest == StoredWorkspaceAuditPolicyAnchor.empty.policyDigest
        else {
            throw EncryptedWorkspaceAuditPolicyStoreError.corruptRecord
        }
    }

    private func encodeAndValidate(
        _ envelope: StoredWorkspaceAuditPolicyEnvelope
    ) throws -> Data {
        do {
            let data = try encoder.encode(envelope)
            guard !data.isEmpty, data.count <= Self.maximumEncodedPolicyBytes else {
                throw EncryptedWorkspaceAuditPolicyStoreError.corruptRecord
            }
            return data
        } catch let error as EncryptedWorkspaceAuditPolicyStoreError {
            throw error
        } catch {
            throw EncryptedWorkspaceAuditPolicyStoreError.corruptRecord
        }
    }

    private func mapCodecReadError(_ error: Error)
        -> EncryptedWorkspaceAuditPolicyStoreError {
        if let error = error as? EncryptedWorkspaceRecordCodecError {
            switch error {
            case .masterKeyMissing:
                return .keyUnavailable
            default:
                return .corruptRecord
            }
        }
        if error is WorkspaceMasterKeyVaultError { return .keyUnavailable }
        return .corruptRecord
    }

    private func mapCodecWriteError(_ error: Error)
        -> EncryptedWorkspaceAuditPolicyStoreError {
        if error is WorkspaceMasterKeyVaultError { return .keyUnavailable }
        if let error = error as? EncryptedWorkspaceRecordCodecError,
           error == .masterKeyMissing {
            return .keyUnavailable
        }
        return .storageUnavailable
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

private struct StoredWorkspaceAuditPolicyEnvelope: Codable {
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let predecessorRevision: UInt64
    let predecessorDigest: Data
    let policy: ConfirmedWorkspaceAuditPolicy
}

private struct LocatedWorkspaceAuditPolicy {
    let record: EncryptedWorkspaceRecord
    let policy: ConfirmedWorkspaceAuditPolicy
    let digest: Data
}

import CryptoKit
import Foundation
import WarRoomCore

/// Redacted failures from durable audited-operation persistence.
public enum EncryptedDurableAuditedOperationStoreError: Error, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible {
    case anchorUnavailable
    case conflictingCorrelationClaim
    case corruptLedger
    case crossWorkspaceOutcome
    case duplicateOutcome
    case ledgerFull(limit: Int)
    case lockUnavailable
    case missingIntent
    case rollbackDetected
    case storageUnavailable

    public var description: String { "Encrypted operation evidence is unavailable." }
    public var debugDescription: String {
        "EncryptedDurableAuditedOperationStoreError(<redacted>)"
    }
}

/// Device-local, workspace-encrypted evidence for one-shot mutating operations.
///
/// A single cooperative-process lock covers claim lookup and persistence across all
/// workspaces, preventing one correlation ID from being claimed concurrently in two
/// scopes. Each workspace ledger is independently sealed with its Keychain-backed
/// AES-256-GCM key and atomically replaced as ciphertext. This store never invokes or
/// retries transport; pending records are exposed only for explicit reconciliation.
public actor EncryptedDurableAuditedOperationStore: DurableAuditedOperationStore {
    static let schemaVersion = 1
    static let maximumOperationsPerWorkspace = 100
    static let collection = try! WorkspaceDataCollection(
        validating: "private.audited-operations.v1"
    )
    static let ledgerRecordID = EncryptedWorkspaceRecordID(
        rawValue: UUID(uuidString: "A7D17000-1ED6-4D1F-AD17-000000000002")!
    )
    static let globalLockScope = WorkspaceID(
        rawValue: UUID(uuidString: "A7D17000-1ED6-4D1F-AD17-FFFFFFFFFFFF")!
    )

    private let dataStore: any AuditedOperationWorkspaceDataStore
    private let codec: EncryptedWorkspaceRecordCodec
    private let anchorVault: any OperationStateAnchorProviding
    private let lockCoordinator: AuditWorkspaceLockCoordinator
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates a store in the app container using non-synchronizing, device-only
    /// Keychain master keys and protected Application Support ciphertext files.
    public init() throws {
        let workspaceRoot = try EncryptedWorkspaceFileDataStore.defaultRootURL()
        // Operation evidence is deliberately outside the mutable workspace-profile
        // tree and uses an independent key namespace. Profile deletion therefore
        // cannot silently erase replay claims or poison the global commitment.
        let recordRoot = workspaceRoot.deletingLastPathComponent()
            .appendingPathComponent("audited-operations", isDirectory: true)
        dataStore = try EncryptedWorkspaceFileDataStore(
            rootURL: recordRoot,
            fileSystem: SystemAtomicWorkspaceFileSystem()
        )
        codec = EncryptedWorkspaceRecordCodec(keyVault: KeychainWorkspaceMasterKeyVault(
            service: "ai.thox.warroom.operation-master-keys",
            keychain: SystemKeychainItemClient()
        ))
        anchorVault = KeychainOperationStateAnchorVault()
        lockCoordinator = try AuditWorkspaceLockCoordinator(
            rootURL: recordRoot.deletingLastPathComponent()
                .appendingPathComponent("operation-locks", isDirectory: true)
        )
        encoder = Self.makeEncoder()
        decoder = Self.makeDecoder()
    }

    init(
        dataStore: any AuditedOperationWorkspaceDataStore,
        codec: EncryptedWorkspaceRecordCodec,
        anchorVault: any OperationStateAnchorProviding,
        lockCoordinator: AuditWorkspaceLockCoordinator = .processLocalForTesting()
    ) {
        self.dataStore = dataStore
        self.codec = codec
        self.anchorVault = anchorVault
        self.lockCoordinator = lockCoordinator
        encoder = Self.makeEncoder()
        decoder = Self.makeDecoder()
    }

    public func appendIntent(
        _ intent: PersistableAuditEvent,
        correlationID: AuditedOperationCorrelationID
    ) async throws -> AuditedOperationIntentAppendResult {
        do {
            return try await lockCoordinator.withLock(for: Self.globalLockScope) { [self] in
                try await appendIntentWhileLocked(intent, correlationID: correlationID)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as EncryptedDurableAuditedOperationStoreError {
            throw error
        } catch {
            throw EncryptedDurableAuditedOperationStoreError.lockUnavailable
        }
    }

    public func appendOutcome(
        _ outcome: PersistableAuditEvent,
        correlationID: AuditedOperationCorrelationID
    ) async throws {
        do {
            try await lockCoordinator.withLock(for: Self.globalLockScope) { [self] in
                try await appendOutcomeWhileLocked(outcome, correlationID: correlationID)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as EncryptedDurableAuditedOperationStoreError {
            throw error
        } catch {
            throw EncryptedDurableAuditedOperationStoreError.lockUnavailable
        }
    }

    public func reconciliationRecords(
        matching query: AuditedOperationReconciliationQuery
    ) async throws -> AuditedOperationReconciliationPage {
        do {
            return try await lockCoordinator.withLock(for: Self.globalLockScope) { [self] in
                try await reconciliationRecordsWhileLocked(matching: query)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as EncryptedDurableAuditedOperationStoreError {
            throw error
        } catch let error as AuditedOperationPersistenceError {
            throw error
        } catch {
            throw EncryptedDurableAuditedOperationStoreError.lockUnavailable
        }
    }

    private func appendIntentWhileLocked(
        _ intent: PersistableAuditEvent,
        correlationID: AuditedOperationCorrelationID
    ) async throws -> AuditedOperationIntentAppendResult {
        try Task.checkCancellation()
        let workspaceID = intent.event.workspaceID
        _ = try validatedRecord(
            workspaceID: workspaceID,
            correlationID: correlationID,
            intent: intent,
            outcome: nil
        )

        let ledgers = try await allLedgers()
        let anchor = try await reconcileAnchor(with: ledgers)
        let claims = ledgers.flatMap(\.ledger.operations).filter {
            $0.correlationID == correlationID
        }
        guard claims.isEmpty else { return .replayRejected }

        let located = ledgers.first { $0.ledger.workspaceID == workspaceID }
        var ledger = located?.ledger ?? StoredOperationLedger(
            schemaVersion: Self.schemaVersion,
            workspaceID: workspaceID,
            mutationRevision: 0,
            predecessorStateDigest: StoredOperationStateAnchor.empty.stateDigest,
            predecessorLedgerDigest: StoredOperationStateAnchor.empty.stateDigest,
            operations: []
        )
        guard ledger.operations.count < Self.maximumOperationsPerWorkspace else {
            throw EncryptedDurableAuditedOperationStoreError.ledgerFull(
                limit: Self.maximumOperationsPerWorkspace
            )
        }
        ledger.operations.append(StoredOperation(
            correlationID: correlationID,
            intent: intent,
            outcome: nil
        ))
        guard anchor.revision < UInt64.max else {
            throw EncryptedDurableAuditedOperationStoreError.ledgerFull(
                limit: Self.maximumOperationsPerWorkspace
            )
        }
        ledger.mutationRevision = anchor.revision + 1
        ledger.predecessorStateDigest = anchor.stateDigest
        ledger.predecessorLedgerDigest = try located.map {
            try ledgerDigest($0.ledger)
        } ?? StoredOperationStateAnchor.empty.stateDigest

        if located == nil {
            do {
                try await codec.provisionMasterKey(for: workspaceID)
            } catch {
                throw EncryptedDurableAuditedOperationStoreError.storageUnavailable
            }
        }
        try await commit(
            ledger,
            replacing: located?.record,
            priorLedgers: ledgers,
            anchor: anchor
        )
        return .appended
    }

    private func appendOutcomeWhileLocked(
        _ outcome: PersistableAuditEvent,
        correlationID: AuditedOperationCorrelationID
    ) async throws {
        try Task.checkCancellation()
        let ledgers = try await allLedgers()
        let anchor = try await reconcileAnchor(with: ledgers)
        let matching = ledgers.compactMap { located -> (LocatedLedger, Int)? in
            guard let index = located.ledger.operations.firstIndex(where: {
                $0.correlationID == correlationID
            }) else { return nil }
            return (located, index)
        }
        guard matching.count == 1, let (located, operationIndex) = matching.first else {
            if matching.isEmpty {
                throw EncryptedDurableAuditedOperationStoreError.missingIntent
            }
            throw EncryptedDurableAuditedOperationStoreError.conflictingCorrelationClaim
        }
        guard located.ledger.workspaceID == outcome.event.workspaceID else {
            throw EncryptedDurableAuditedOperationStoreError.crossWorkspaceOutcome
        }
        guard located.ledger.operations[operationIndex].outcome == nil else {
            throw EncryptedDurableAuditedOperationStoreError.duplicateOutcome
        }
        _ = try validatedRecord(
            workspaceID: located.ledger.workspaceID,
            correlationID: correlationID,
            intent: located.ledger.operations[operationIndex].intent,
            outcome: outcome
        )

        var replacement = located.ledger
        replacement.operations[operationIndex].outcome = outcome
        guard anchor.revision < UInt64.max else {
            throw EncryptedDurableAuditedOperationStoreError.ledgerFull(
                limit: Self.maximumOperationsPerWorkspace
            )
        }
        replacement.mutationRevision = anchor.revision + 1
        replacement.predecessorStateDigest = anchor.stateDigest
        replacement.predecessorLedgerDigest = try ledgerDigest(located.ledger)
        try await commit(
            replacement,
            replacing: located.record,
            priorLedgers: ledgers,
            anchor: anchor
        )
    }

    private func reconciliationRecordsWhileLocked(
        matching query: AuditedOperationReconciliationQuery
    ) async throws -> AuditedOperationReconciliationPage {
        try Task.checkCancellation()
        let ledgers = try await allLedgers()
        _ = try await reconcileAnchor(with: ledgers)
        let located = ledgers.first { $0.ledger.workspaceID == query.workspaceID }
        let matches = try (located?.ledger.operations ?? []).compactMap { operation
            -> AuditedOperationReconciliationRecord? in
            let record = try validatedRecord(
                workspaceID: query.workspaceID,
                correlationID: operation.correlationID,
                intent: operation.intent,
                outcome: operation.outcome
            )
            return record.status == query.status ? record : nil
        }.sorted {
            if $0.intent.event.occurredAt == $1.intent.event.occurredAt {
                return $0.correlationID.description < $1.correlationID.description
            }
            return $0.intent.event.occurredAt < $1.intent.event.occurredAt
        }
        let pageRecords = Array(matches.prefix(query.limit.rawValue))
        return try AuditedOperationReconciliationPage(
            workspaceID: query.workspaceID,
            status: query.status,
            records: pageRecords,
            truncated: matches.count > pageRecords.count
        )
    }

    private func allLedgers() async throws -> [LocatedLedger] {
        let workspaceIDs: [WorkspaceID]
        do {
            workspaceIDs = try await dataStore.workspaceIDs()
        } catch {
            throw EncryptedDurableAuditedOperationStoreError.storageUnavailable
        }
        var result: [LocatedLedger] = []
        for workspaceID in workspaceIDs {
            try Task.checkCancellation()
            if let located = try await ledger(for: workspaceID) {
                result.append(located)
            }
        }
        return result
    }

    private func ledger(for workspaceID: WorkspaceID) async throws -> LocatedLedger? {
        let record: EncryptedWorkspaceRecord?
        do {
            record = try await dataStore.record(id: Self.ledgerRecordID, in: workspaceID)
        } catch {
            throw EncryptedDurableAuditedOperationStoreError.storageUnavailable
        }
        guard let record else { return nil }
        guard record.workspaceID == workspaceID,
              record.collection == Self.collection,
              record.id == Self.ledgerRecordID else {
            throw EncryptedDurableAuditedOperationStoreError.corruptLedger
        }
        let plaintext: Data
        do {
            plaintext = try await codec.open(record)
        } catch {
            throw EncryptedDurableAuditedOperationStoreError.corruptLedger
        }
        guard plaintext.count <= EncryptedWorkspaceRecordCodec.maximumPlaintextBytes else {
            throw EncryptedDurableAuditedOperationStoreError.corruptLedger
        }
        let decoded: StoredOperationLedger
        do {
            decoded = try decoder.decode(StoredOperationLedger.self, from: plaintext)
        } catch {
            throw EncryptedDurableAuditedOperationStoreError.corruptLedger
        }
        try validate(decoded, workspaceID: workspaceID)
        return LocatedLedger(record: record, ledger: decoded)
    }

    private func validate(
        _ ledger: StoredOperationLedger,
        workspaceID: WorkspaceID
    ) throws {
        guard ledger.schemaVersion == Self.schemaVersion,
              ledger.workspaceID == workspaceID,
              ledger.mutationRevision > 0,
              ledger.predecessorStateDigest.count == StoredOperationStateAnchor.digestByteCount,
              ledger.predecessorLedgerDigest.count == StoredOperationStateAnchor.digestByteCount,
              ledger.operations.count <= Self.maximumOperationsPerWorkspace,
              Set(ledger.operations.map(\.correlationID)).count == ledger.operations.count else {
            throw EncryptedDurableAuditedOperationStoreError.corruptLedger
        }
        for operation in ledger.operations {
            do {
                _ = try validatedRecord(
                    workspaceID: workspaceID,
                    correlationID: operation.correlationID,
                    intent: operation.intent,
                    outcome: operation.outcome
                )
            } catch {
                throw EncryptedDurableAuditedOperationStoreError.corruptLedger
            }
        }
        let canonical: Data
        do {
            canonical = try encoder.encode(ledger)
        } catch {
            throw EncryptedDurableAuditedOperationStoreError.corruptLedger
        }
        guard canonical.count <= EncryptedWorkspaceRecordCodec.maximumPlaintextBytes else {
            throw EncryptedDurableAuditedOperationStoreError.corruptLedger
        }
    }

    private func validatedRecord(
        workspaceID: WorkspaceID,
        correlationID: AuditedOperationCorrelationID,
        intent: PersistableAuditEvent,
        outcome: PersistableAuditEvent?
    ) throws -> AuditedOperationReconciliationRecord {
        do {
            return try AuditedOperationReconciliationRecord(
                workspaceID: workspaceID,
                correlationID: correlationID,
                intent: PersistableAuditEvent(event: intent.event),
                outcome: try outcome.map { try PersistableAuditEvent(event: $0.event) }
            )
        } catch {
            throw EncryptedDurableAuditedOperationStoreError.corruptLedger
        }
    }

    private func commit(
        _ ledger: StoredOperationLedger,
        replacing record: EncryptedWorkspaceRecord?,
        priorLedgers: [LocatedLedger],
        anchor: StoredOperationStateAnchor
    ) async throws {
        try validate(ledger, workspaceID: ledger.workspaceID)
        let plaintext: Data
        do {
            plaintext = try encoder.encode(ledger)
        } catch {
            throw EncryptedDurableAuditedOperationStoreError.corruptLedger
        }
        guard plaintext.count <= EncryptedWorkspaceRecordCodec.maximumPlaintextBytes else {
            throw EncryptedDurableAuditedOperationStoreError.ledgerFull(
                limit: Self.maximumOperationsPerWorkspace
            )
        }
        do {
            let createdAt = record?.createdAt ?? Date()
            let replacement = try await codec.seal(
                plaintext,
                workspaceID: ledger.workspaceID,
                collection: Self.collection,
                recordID: Self.ledgerRecordID,
                createdAt: createdAt,
                updatedAt: max(record?.updatedAt ?? createdAt, Date())
            )
            try await dataStore.save(replacement)
            var committedLedgers = priorLedgers
            if let index = committedLedgers.firstIndex(where: {
                $0.ledger.workspaceID == ledger.workspaceID
            }) {
                committedLedgers[index] = LocatedLedger(record: replacement, ledger: ledger)
            } else {
                committedLedgers.append(LocatedLedger(record: replacement, ledger: ledger))
            }
            let commitment = try stateCommitment(for: committedLedgers)
            guard commitment.revision == anchor.revision + 1 else {
                throw EncryptedDurableAuditedOperationStoreError.corruptLedger
            }
            try await anchorVault.store(commitment)
        } catch let error as EncryptedDurableAuditedOperationStoreError {
            throw error
        } catch is OperationStateAnchorVaultError {
            throw EncryptedDurableAuditedOperationStoreError.anchorUnavailable
        } catch {
            throw EncryptedDurableAuditedOperationStoreError.storageUnavailable
        }
    }

    private func reconcileAnchor(
        with ledgers: [LocatedLedger]
    ) async throws -> StoredOperationStateAnchor {
        let commitment = try stateCommitment(for: ledgers)
        let stored: StoredOperationStateAnchor
        do {
            if let existing = try await anchorVault.anchor() {
                stored = existing
            } else {
                guard ledgers.isEmpty else {
                    throw EncryptedDurableAuditedOperationStoreError.rollbackDetected
                }
                stored = try await anchorVault.initializeEmptyAnchor()
            }
        } catch let error as EncryptedDurableAuditedOperationStoreError {
            throw error
        } catch {
            throw EncryptedDurableAuditedOperationStoreError.anchorUnavailable
        }

        if commitment == stored { return stored }
        guard commitment.revision == stored.revision + 1 else {
            throw EncryptedDurableAuditedOperationStoreError.rollbackDetected
        }
        let crashCandidates = ledgers.filter {
            $0.ledger.mutationRevision == commitment.revision
                && $0.ledger.predecessorStateDigest == stored.stateDigest
        }
        guard crashCandidates.count == 1,
              let candidate = crashCandidates.first,
              try predecessorCommitment(
                  before: candidate.ledger,
                  in: ledgers,
                  revision: stored.revision
              ) == stored else {
            throw EncryptedDurableAuditedOperationStoreError.rollbackDetected
        }
        do {
            try await anchorVault.store(commitment)
            return commitment
        } catch {
            throw EncryptedDurableAuditedOperationStoreError.anchorUnavailable
        }
    }

    private func stateCommitment(
        for ledgers: [LocatedLedger]
    ) throws -> StoredOperationStateAnchor {
        guard !ledgers.isEmpty else { return .empty }
        let sortedLedgers = ledgers.map(\.ledger).sorted {
            $0.workspaceID.rawValue.uuidString < $1.workspaceID.rawValue.uuidString
        }
        guard let revision = sortedLedgers.map(\.mutationRevision).max(),
              revision > 0 else {
            throw EncryptedDurableAuditedOperationStoreError.corruptLedger
        }
        return try StoredOperationStateAnchor.validated(
            revision: revision,
            stateDigest: try globalStateDigest(for: sortedLedgers)
        )
    }

    private func predecessorCommitment(
        before candidate: StoredOperationLedger,
        in ledgers: [LocatedLedger],
        revision: UInt64
    ) throws -> StoredOperationStateAnchor {
        var digests: [StoredWorkspaceLedgerDigest] = []
        for located in ledgers {
            if located.ledger.workspaceID == candidate.workspaceID {
                if candidate.predecessorLedgerDigest != StoredOperationStateAnchor.empty.stateDigest {
                    digests.append(StoredWorkspaceLedgerDigest(
                        workspaceID: candidate.workspaceID,
                        digest: candidate.predecessorLedgerDigest
                    ))
                }
            } else {
                digests.append(StoredWorkspaceLedgerDigest(
                    workspaceID: located.ledger.workspaceID,
                    digest: try ledgerDigest(located.ledger)
                ))
            }
        }
        return try StoredOperationStateAnchor.validated(
            revision: revision,
            stateDigest: try digestWorkspaceLedgers(digests)
        )
    }

    private func globalStateDigest(
        for ledgers: [StoredOperationLedger]
    ) throws -> Data {
        let digests = try ledgers.map {
            StoredWorkspaceLedgerDigest(
                workspaceID: $0.workspaceID,
                digest: try ledgerDigest($0)
            )
        }
        return try digestWorkspaceLedgers(digests)
    }

    private func ledgerDigest(_ ledger: StoredOperationLedger) throws -> Data {
        let encoded: Data
        do {
            encoded = try encoder.encode(ledger)
        } catch {
            throw EncryptedDurableAuditedOperationStoreError.corruptLedger
        }
        return Data(SHA256.hash(data: encoded))
    }

    private func digestWorkspaceLedgers(
        _ digests: [StoredWorkspaceLedgerDigest]
    ) throws -> Data {
        guard !digests.isEmpty else {
            return StoredOperationStateAnchor.empty.stateDigest
        }
        let sorted = digests.sorted {
            $0.workspaceID.rawValue.uuidString < $1.workspaceID.rawValue.uuidString
        }
        let encoded: Data
        do {
            encoded = try encoder.encode(sorted)
        } catch {
            throw EncryptedDurableAuditedOperationStoreError.corruptLedger
        }
        return Data(SHA256.hash(data: encoded))
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

protocol AuditedOperationWorkspaceDataStore: EncryptedWorkspaceDataStore {
    func workspaceIDs() async throws -> [WorkspaceID]
}

extension EncryptedWorkspaceFileDataStore: AuditedOperationWorkspaceDataStore {}

private struct StoredOperationLedger: Codable, Sendable {
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    var mutationRevision: UInt64
    var predecessorStateDigest: Data
    var predecessorLedgerDigest: Data
    var operations: [StoredOperation]
}

private struct StoredWorkspaceLedgerDigest: Codable, Sendable {
    let workspaceID: WorkspaceID
    let digest: Data
}

private struct StoredOperation: Codable, Sendable {
    let correlationID: AuditedOperationCorrelationID
    let intent: PersistableAuditEvent
    var outcome: PersistableAuditEvent?
}

private struct LocatedLedger: Sendable {
    let record: EncryptedWorkspaceRecord
    let ledger: StoredOperationLedger
}

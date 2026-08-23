import CryptoKit
import Foundation
import WarRoomCore

/// Redacted failures from encrypted durable audit persistence.
public enum EncryptedDurableAuditStoreError: Error, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible {
    case anchorUnavailable
    case conflictingEventIdentifier
    case corruptAnchor
    case corruptLedger
    case invalidCursor
    case ledgerFull(limit: Int)
    case lockUnavailable
    case rollbackDetected
    case storageUnavailable

    public var description: String { "Encrypted audit history is unavailable." }
    public var debugDescription: String { "EncryptedDurableAuditStoreError(<redacted>)" }
}

/// Workspace-isolated, encrypted implementation of the durable audit boundary.
///
/// Each workspace owns one atomically replaced AES-256-GCM record. Entries are also
/// linked by SHA-256 digests so decoding rejects internal deletion, reordering, or
/// substitution. A separately protected Keychain head commits the entry count and
/// chain digest to detect replacement by an older, otherwise valid ciphertext.
/// A process-wide workspace lock plus an app-container advisory file lock serializes
/// the complete record-and-anchor transaction across store instances and processes.
public actor EncryptedDurableAuditEventStore: DurableAuditEventStore, AuditLifecycleManaging {
    static let schemaVersion = 2
    static let legacySchemaVersion = 1
    static let maximumEntries = 10_000
    static let collection = try! WorkspaceDataCollection(validating: "private.audit.v1")
    static let recordID = EncryptedWorkspaceRecordID(
        rawValue: UUID(uuidString: "A7D17000-1ED6-4D1F-AD17-000000000001")!
    )

    private let dataStore: any EncryptedWorkspaceDataStore
    private let codec: EncryptedWorkspaceRecordCodec
    private let anchorVault: any AuditHeadAnchorProviding
    private let lockCoordinator: AuditWorkspaceLockCoordinator
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates an audit store in the app container backed by device-only Keychain keys.
    public init() throws {
        let recordRoot = try EncryptedWorkspaceFileDataStore.defaultRootURL()
        dataStore = try EncryptedWorkspaceFileDataStore(
            rootURL: recordRoot,
            fileSystem: SystemAtomicWorkspaceFileSystem()
        )
        codec = EncryptedWorkspaceRecordCodec()
        anchorVault = KeychainAuditHeadAnchorVault()
        lockCoordinator = try AuditWorkspaceLockCoordinator(
            rootURL: recordRoot.deletingLastPathComponent()
                .appendingPathComponent("audit-locks", isDirectory: true)
        )
        encoder = Self.makeEncoder()
        decoder = Self.makeDecoder()
    }

    init(
        dataStore: any EncryptedWorkspaceDataStore,
        codec: EncryptedWorkspaceRecordCodec,
        anchorVault: any AuditHeadAnchorProviding,
        lockCoordinator: AuditWorkspaceLockCoordinator = .processLocalForTesting()
    ) {
        self.dataStore = dataStore
        self.codec = codec
        self.anchorVault = anchorVault
        self.lockCoordinator = lockCoordinator
        encoder = Self.makeEncoder()
        decoder = Self.makeDecoder()
    }

    public func append(_ event: PersistableAuditEvent) async throws {
        do {
            try await lockCoordinator.withLock(for: event.event.workspaceID) { [self] in
                try await appendWhileLocked(event)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as EncryptedDurableAuditStoreError {
            throw error
        } catch {
            throw EncryptedDurableAuditStoreError.lockUnavailable
        }
    }

    private func appendWhileLocked(_ event: PersistableAuditEvent) async throws {
        try Task.checkCancellation()
        // Revalidation is intentional even though callers hold a validated wrapper.
        let validated: PersistableAuditEvent
        do {
            validated = try PersistableAuditEvent(event: event.event)
        } catch {
            throw EncryptedDurableAuditStoreError.corruptLedger
        }

        let existingRecord: EncryptedWorkspaceRecord?
        do {
            existingRecord = try await dataStore.record(
                id: Self.recordID,
                in: validated.event.workspaceID
            )
        } catch {
            throw EncryptedDurableAuditStoreError.storageUnavailable
        }

        var ledger: StoredAuditLedger
        if let existingRecord {
            ledger = try await openLedger(existingRecord, workspaceID: validated.event.workspaceID)
            try await reconcileAnchor(for: ledger, requiresExistingAnchor: true)
        } else {
            let anchor = try await initializeAnchor(for: validated.event.workspaceID)
            guard anchor.entryCount == 0 else {
                throw EncryptedDurableAuditStoreError.rollbackDetected
            }
            do {
                // Provisioning is safe only after the workspace-scoped record lookup
                // proved that no audit ciphertext exists.
                try await codec.provisionMasterKey(for: validated.event.workspaceID)
            } catch {
                throw EncryptedDurableAuditStoreError.storageUnavailable
            }
            ledger = StoredAuditLedger(
                schemaVersion: Self.schemaVersion,
                workspaceID: validated.event.workspaceID,
                generation: 0,
                lifetimeEventCount: 0,
                generationBaseEntryCount: 0,
                generationBaseLifetimeEventCount: 0,
                predecessor: nil,
                entries: []
            )
        }

        if let prior = ledger.entries.first(where: { $0.event.event.id == validated.event.id }) {
            guard prior.event == validated else {
                throw EncryptedDurableAuditStoreError.conflictingEventIdentifier
            }
            return
        }
        guard ledger.entries.count < Self.maximumEntries else {
            throw EncryptedDurableAuditStoreError.ledgerFull(limit: Self.maximumEntries)
        }

        guard ledger.lifetimeEventCount < UInt64.max else {
            throw EncryptedDurableAuditStoreError.ledgerFull(limit: Self.maximumEntries)
        }
        let sequence = UInt64(ledger.entries.count)
        let previousDigest = ledger.entries.last?.digest ?? Data(repeating: 0, count: 32)
        let digest = try digest(
            workspaceID: ledger.workspaceID,
            sequence: sequence,
            previousDigest: previousDigest,
            event: validated
        )
        ledger.entries.append(StoredAuditEntry(
            sequence: sequence,
            previousDigest: previousDigest,
            digest: digest,
            event: validated
        ))
        ledger.lifetimeEventCount += 1

        let plaintext: Data
        do {
            plaintext = try encoder.encode(ledger)
        } catch {
            throw EncryptedDurableAuditStoreError.corruptLedger
        }
        guard plaintext.count <= EncryptedWorkspaceRecordCodec.maximumPlaintextBytes else {
            throw EncryptedDurableAuditStoreError.ledgerFull(
                limit: EncryptedWorkspaceRecordCodec.maximumPlaintextBytes
            )
        }

        let createdAt = existingRecord?.createdAt ?? Date()
        let updatedAt = max(existingRecord?.updatedAt ?? createdAt, Date())
        do {
            let record = try await codec.seal(
                plaintext,
                workspaceID: ledger.workspaceID,
                collection: Self.collection,
                recordID: Self.recordID,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
            try await dataStore.save(record)
            // The encrypted record is durable before its independently protected
            // commitment advances. A crash in between is recovered on next open.
            try await anchorVault.store(
                try anchor(for: ledger),
                for: ledger.workspaceID
            )
        } catch let error as EncryptedDurableAuditStoreError {
            throw error
        } catch let error as AuditHeadAnchorVaultError {
            throw mapAnchorError(error)
        } catch {
            throw EncryptedDurableAuditStoreError.storageUnavailable
        }
    }

    public func events(matching query: AuditEventQuery) async throws -> AuditEventPage {
        do {
            return try await lockCoordinator.withLock(for: query.workspaceID) { [self] in
                try await eventsWhileLocked(matching: query)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as EncryptedDurableAuditStoreError {
            throw error
        } catch {
            throw EncryptedDurableAuditStoreError.lockUnavailable
        }
    }

    private func eventsWhileLocked(matching query: AuditEventQuery) async throws
        -> AuditEventPage {
        try Task.checkCancellation()
        let record: EncryptedWorkspaceRecord?
        do {
            record = try await dataStore.record(id: Self.recordID, in: query.workspaceID)
        } catch {
            throw EncryptedDurableAuditStoreError.storageUnavailable
        }
        guard let record else {
            let anchor = try await readAnchor(for: query.workspaceID)
            guard anchor == nil || anchor == .empty else {
                throw EncryptedDurableAuditStoreError.rollbackDetected
            }
            if query.after != nil {
                throw EncryptedDurableAuditStoreError.invalidCursor
            }
            return try AuditEventPage(workspaceID: query.workspaceID, events: [])
        }

        let ledger = try await openLedger(record, workspaceID: query.workspaceID)
        try await reconcileAnchor(for: ledger, requiresExistingAnchor: true)
        let start = try cursorOffset(query.after, in: ledger)
        var result: [PersistableAuditEvent] = []
        var index = start
        while index < ledger.entries.count, result.count < query.limit.rawValue {
            try Task.checkCancellation()
            let event = ledger.entries[index].event
            if matches(event.event.occurredAt, query: query) {
                result.append(event)
            }
            index += 1
        }

        // Avoid cursors that lead only to an empty terminal page.
        var hasAnotherMatch = false
        var probe = index
        while probe < ledger.entries.count {
            if matches(ledger.entries[probe].event.event.occurredAt, query: query) {
                hasAnotherMatch = true
                break
            }
            probe += 1
        }
        let nextCursor = try hasAnotherMatch ? makeCursor(offset: index, ledger: ledger) : nil
        return try AuditEventPage(
            workspaceID: query.workspaceID,
            events: result,
            nextCursor: nextCursor
        )
    }

    /// Applies an explicit retention policy without writing plaintext intermediates.
    public func applyRetention(
        _ policy: AuditRetentionPolicy,
        to workspaceID: WorkspaceID,
        asOf: Date = Date()
    ) async throws -> AuditRetentionResult {
        do {
            return try await lockCoordinator.withLock(for: workspaceID) { [self] in
                try await applyRetentionWhileLocked(policy, to: workspaceID, asOf: asOf)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as EncryptedDurableAuditStoreError {
            throw error
        } catch let error as AuditLifecycleError {
            throw error
        } catch {
            throw EncryptedDurableAuditStoreError.lockUnavailable
        }
    }

    /// Produces a bounded redacted snapshot entirely in memory after ledger verification.
    public func exportSnapshot(
        _ request: AuditExportRequest,
        generatedAt: Date = Date()
    ) async throws -> RedactedAuditExportSnapshot {
        do {
            return try await lockCoordinator.withLock(for: request.workspaceID) { [self] in
                try await exportSnapshotWhileLocked(request, generatedAt: generatedAt)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as EncryptedDurableAuditStoreError {
            throw error
        } catch let error as AuditLifecycleError {
            throw error
        } catch {
            throw EncryptedDurableAuditStoreError.lockUnavailable
        }
    }

    private func applyRetentionWhileLocked(
        _ policy: AuditRetentionPolicy,
        to workspaceID: WorkspaceID,
        asOf: Date
    ) async throws -> AuditRetentionResult {
        try Task.checkCancellation()
        guard asOf.timeIntervalSinceReferenceDate.isFinite else {
            throw AuditLifecycleError.invalidRetentionResult
        }
        let record: EncryptedWorkspaceRecord?
        do {
            record = try await dataStore.record(id: Self.recordID, in: workspaceID)
        } catch {
            throw EncryptedDurableAuditStoreError.storageUnavailable
        }
        guard let record else {
            let storedAnchor = try await readAnchor(for: workspaceID)
            guard storedAnchor == nil || storedAnchor == .empty else {
                throw EncryptedDurableAuditStoreError.rollbackDetected
            }
            let cutoff = try retentionCutoff(policy: policy, asOf: asOf)
            return try AuditRetentionResult(
                workspaceID: workspaceID,
                policy: policy,
                cutoff: cutoff,
                priorRetainedEventCount: 0,
                retainedEventCount: 0,
                prunedEventCount: 0,
                lifetimeEventCount: 0
            )
        }

        let ledger = try await openLedger(record, workspaceID: workspaceID)
        try await reconcileAnchor(for: ledger, requiresExistingAnchor: true)
        let cutoff = try retentionCutoff(policy: policy, asOf: asOf)
        guard let cutoff else {
            return try AuditRetentionResult(
                workspaceID: workspaceID,
                policy: policy,
                cutoff: nil,
                priorRetainedEventCount: ledger.entries.count,
                retainedEventCount: ledger.entries.count,
                prunedEventCount: 0,
                lifetimeEventCount: ledger.lifetimeEventCount
            )
        }
        let retainedEvents = ledger.entries.compactMap { entry in
            entry.event.event.occurredAt >= cutoff ? entry.event : nil
        }
        let prunedCount = ledger.entries.count - retainedEvents.count
        guard prunedCount > 0 else {
            return try AuditRetentionResult(
                workspaceID: workspaceID,
                policy: policy,
                cutoff: cutoff,
                priorRetainedEventCount: ledger.entries.count,
                retainedEventCount: ledger.entries.count,
                prunedEventCount: 0,
                lifetimeEventCount: ledger.lifetimeEventCount
            )
        }
        guard ledger.generation < UInt64.max else {
            throw EncryptedDurableAuditStoreError.ledgerFull(limit: Self.maximumEntries)
        }

        var retainedEntries: [StoredAuditEntry] = []
        retainedEntries.reserveCapacity(retainedEvents.count)
        var previousDigest = StoredAuditHeadAnchor.empty.headDigest
        for (index, event) in retainedEvents.enumerated() {
            try Task.checkCancellation()
            let digest = try digest(
                workspaceID: workspaceID,
                sequence: UInt64(index),
                previousDigest: previousDigest,
                event: event
            )
            retainedEntries.append(StoredAuditEntry(
                sequence: UInt64(index),
                previousDigest: previousDigest,
                digest: digest,
                event: event
            ))
            previousDigest = digest
        }
        let retainedLedger = StoredAuditLedger(
            schemaVersion: Self.schemaVersion,
            workspaceID: workspaceID,
            generation: ledger.generation + 1,
            lifetimeEventCount: ledger.lifetimeEventCount,
            generationBaseEntryCount: UInt64(retainedEntries.count),
            generationBaseLifetimeEventCount: ledger.lifetimeEventCount,
            predecessor: commitment(for: ledger),
            entries: retainedEntries
        )
        try validateIntegrity(of: retainedLedger)
        try await saveLedger(retainedLedger, replacing: record)
        return try AuditRetentionResult(
            workspaceID: workspaceID,
            policy: policy,
            cutoff: cutoff,
            priorRetainedEventCount: ledger.entries.count,
            retainedEventCount: retainedEntries.count,
            prunedEventCount: prunedCount,
            lifetimeEventCount: ledger.lifetimeEventCount
        )
    }

    private func exportSnapshotWhileLocked(
        _ request: AuditExportRequest,
        generatedAt: Date
    ) async throws -> RedactedAuditExportSnapshot {
        try Task.checkCancellation()
        guard generatedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw AuditLifecycleError.invalidExportSnapshot
        }
        let record: EncryptedWorkspaceRecord?
        do {
            record = try await dataStore.record(id: Self.recordID, in: request.workspaceID)
        } catch {
            throw EncryptedDurableAuditStoreError.storageUnavailable
        }
        let ledger: StoredAuditLedger
        if let record {
            ledger = try await openLedger(record, workspaceID: request.workspaceID)
            try await reconcileAnchor(for: ledger, requiresExistingAnchor: true)
        } else {
            let storedAnchor = try await readAnchor(for: request.workspaceID)
            guard storedAnchor == nil || storedAnchor == .empty else {
                throw EncryptedDurableAuditStoreError.rollbackDetected
            }
            ledger = StoredAuditLedger(
                schemaVersion: Self.schemaVersion,
                workspaceID: request.workspaceID,
                generation: 0,
                lifetimeEventCount: 0,
                generationBaseEntryCount: 0,
                generationBaseLifetimeEventCount: 0,
                predecessor: nil,
                entries: []
            )
        }

        var exported: [RedactedAuditExportEvent] = []
        exported.reserveCapacity(min(request.limit.rawValue, ledger.entries.count))
        var matchingCount = 0
        for entry in ledger.entries {
            try Task.checkCancellation()
            let occurredAt = entry.event.event.occurredAt
            if let lower = request.occurredOnOrAfter, occurredAt < lower { continue }
            if let upper = request.occurredBefore, occurredAt >= upper { continue }
            matchingCount += 1
            guard exported.count < request.limit.rawValue else { continue }
            exported.append(exportEvent(entry))
        }
        let sourceHead = ledger.entries.last?.digest ?? StoredAuditHeadAnchor.empty.headDigest
        let payload = StoredAuditExportDigestPayload(
            schemaVersion: RedactedAuditExportSnapshot.schemaVersion,
            generatedAt: generatedAt,
            workspaceID: request.workspaceID,
            occurredOnOrAfter: request.occurredOnOrAfter,
            occurredBefore: request.occurredBefore,
            applicationVersion: request.applicationVersion,
            ledgerGeneration: ledger.generation,
            retainedEventCount: ledger.entries.count,
            lifetimeEventCount: ledger.lifetimeEventCount,
            sourceHeadSHA256: hex(sourceHead),
            events: exported,
            truncated: matchingCount > exported.count
        )
        let payloadData = try encoder.encode(payload)
        guard payloadData.count <= RedactedAuditExportSnapshot.maximumEncodedBytes else {
            throw AuditLifecycleError.exportTooLarge(
                limit: RedactedAuditExportSnapshot.maximumEncodedBytes
            )
        }
        let integrity = try AuditExportIntegrity(
            ledgerGeneration: ledger.generation,
            retainedEventCount: ledger.entries.count,
            lifetimeEventCount: ledger.lifetimeEventCount,
            sourceHeadSHA256: hex(sourceHead),
            snapshotSHA256: hex(Data(SHA256.hash(data: payloadData)))
        )
        let snapshot = try RedactedAuditExportSnapshot(
            generatedAt: generatedAt,
            workspaceID: request.workspaceID,
            occurredOnOrAfter: request.occurredOnOrAfter,
            occurredBefore: request.occurredBefore,
            applicationVersion: request.applicationVersion,
            events: exported,
            truncated: matchingCount > exported.count,
            integrity: integrity
        )
        guard try encoder.encode(snapshot).count <= RedactedAuditExportSnapshot.maximumEncodedBytes else {
            throw AuditLifecycleError.exportTooLarge(
                limit: RedactedAuditExportSnapshot.maximumEncodedBytes
            )
        }
        return snapshot
    }

    private func retentionCutoff(policy: AuditRetentionPolicy, asOf: Date) throws -> Date? {
        switch policy {
        case .indefinite:
            return nil
        case .finite(let days):
            let cutoff = asOf.addingTimeInterval(-Double(days.rawValue) * 86_400)
            guard cutoff.timeIntervalSinceReferenceDate.isFinite else {
                throw AuditLifecycleError.invalidRetentionResult
            }
            return cutoff
        }
    }

    private func saveLedger(
        _ ledger: StoredAuditLedger,
        replacing record: EncryptedWorkspaceRecord
    ) async throws {
        let plaintext: Data
        do {
            plaintext = try encoder.encode(ledger)
        } catch {
            throw EncryptedDurableAuditStoreError.corruptLedger
        }
        guard plaintext.count <= EncryptedWorkspaceRecordCodec.maximumPlaintextBytes else {
            throw EncryptedDurableAuditStoreError.ledgerFull(
                limit: EncryptedWorkspaceRecordCodec.maximumPlaintextBytes
            )
        }
        do {
            let replacement = try await codec.seal(
                plaintext,
                workspaceID: ledger.workspaceID,
                collection: Self.collection,
                recordID: Self.recordID,
                createdAt: record.createdAt,
                updatedAt: max(record.updatedAt, Date())
            )
            try await dataStore.save(replacement)
            try await anchorVault.store(try anchor(for: ledger), for: ledger.workspaceID)
        } catch let error as EncryptedDurableAuditStoreError {
            throw error
        } catch let error as AuditHeadAnchorVaultError {
            throw mapAnchorError(error)
        } catch {
            throw EncryptedDurableAuditStoreError.storageUnavailable
        }
    }

    private func exportEvent(_ entry: StoredAuditEntry) -> RedactedAuditExportEvent {
        let event = entry.event.event
        var metadata: [String: RedactedAuditValue] = [:]
        let allowedKeyCharacters = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "._-")
        )
        for key in event.metadata.keys.sorted() {
            guard key.unicodeScalars.allSatisfy(allowedKeyCharacters.contains),
                  let value = event.metadata[key] else { continue }
            switch value {
            case .string, .redacted:
                metadata[key] = .redacted
            case .integer(let integer):
                metadata[key] = .integer(integer)
            case .boolean(let boolean):
                metadata[key] = .boolean(boolean)
            }
        }
        return RedactedAuditExportEvent(
            sourceSequence: entry.sequence,
            id: event.id,
            occurredAt: event.occurredAt,
            category: exportLabel(event.category),
            action: exportLabel(event.action),
            outcome: event.outcome,
            metadata: metadata
        )
    }

    private func exportLabel(_ value: String) -> String {
        if value.contains("/") || value.contains("\\") || value.contains("://")
            || value.hasPrefix("~") {
            return "<redacted>"
        }
        return value
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func initializeAnchor(for workspaceID: WorkspaceID) async throws
        -> StoredAuditHeadAnchor {
        do {
            return try await anchorVault.initializeEmptyAnchor(for: workspaceID)
        } catch let error as AuditHeadAnchorVaultError {
            throw mapAnchorError(error)
        } catch {
            throw EncryptedDurableAuditStoreError.anchorUnavailable
        }
    }

    private func readAnchor(for workspaceID: WorkspaceID) async throws
        -> StoredAuditHeadAnchor? {
        do {
            return try await anchorVault.anchor(for: workspaceID)
        } catch let error as AuditHeadAnchorVaultError {
            throw mapAnchorError(error)
        } catch {
            throw EncryptedDurableAuditStoreError.anchorUnavailable
        }
    }

    private func reconcileAnchor(
        for ledger: StoredAuditLedger,
        requiresExistingAnchor: Bool
    ) async throws {
        let stored = try await readAnchor(for: ledger.workspaceID)
        guard let stored else {
            if requiresExistingAnchor {
                throw EncryptedDurableAuditStoreError.corruptAnchor
            }
            return
        }
        let ledgerCount = UInt64(ledger.entries.count)
        let shouldAdvance: Bool
        if ledger.generation == stored.ledgerGeneration {
            guard ledgerCount >= stored.entryCount,
                  ledger.lifetimeEventCount >= stored.lifetimeEventCount,
                  ledgerCount - stored.entryCount
                    == ledger.lifetimeEventCount - stored.lifetimeEventCount,
                  try digest(atEntryCount: stored.entryCount, in: ledger) == stored.headDigest else {
                throw EncryptedDurableAuditStoreError.rollbackDetected
            }
            shouldAdvance = ledgerCount > stored.entryCount
        } else if stored.ledgerGeneration < UInt64.max,
                  ledger.generation == stored.ledgerGeneration + 1 {
            guard ledger.predecessor == commitment(for: stored),
                  ledger.lifetimeEventCount == stored.lifetimeEventCount,
                  ledger.generationBaseLifetimeEventCount == stored.lifetimeEventCount,
                  ledger.generationBaseEntryCount == ledgerCount else {
                throw EncryptedDurableAuditStoreError.rollbackDetected
            }
            shouldAdvance = true
        } else {
            throw EncryptedDurableAuditStoreError.rollbackDetected
        }
        guard shouldAdvance else { return }

        do {
            try await anchorVault.store(
                try anchor(for: ledger),
                for: ledger.workspaceID
            )
        } catch let error as AuditHeadAnchorVaultError {
            throw mapAnchorError(error)
        } catch {
            throw EncryptedDurableAuditStoreError.anchorUnavailable
        }
    }

    private func anchor(for ledger: StoredAuditLedger) throws -> StoredAuditHeadAnchor {
        let digest = ledger.entries.last?.digest ?? StoredAuditHeadAnchor.empty.headDigest
        do {
            return try StoredAuditHeadAnchor.validated(
                ledgerGeneration: ledger.generation,
                entryCount: UInt64(ledger.entries.count),
                lifetimeEventCount: ledger.lifetimeEventCount,
                headDigest: digest
            )
        } catch {
            throw EncryptedDurableAuditStoreError.corruptLedger
        }
    }

    private func commitment(for anchor: StoredAuditHeadAnchor) -> StoredAuditLedgerCommitment {
        StoredAuditLedgerCommitment(
            generation: anchor.ledgerGeneration,
            entryCount: anchor.entryCount,
            lifetimeEventCount: anchor.lifetimeEventCount,
            headDigest: anchor.headDigest
        )
    }

    private func commitment(for ledger: StoredAuditLedger) -> StoredAuditLedgerCommitment {
        StoredAuditLedgerCommitment(
            generation: ledger.generation,
            entryCount: UInt64(ledger.entries.count),
            lifetimeEventCount: ledger.lifetimeEventCount,
            headDigest: ledger.entries.last?.digest ?? StoredAuditHeadAnchor.empty.headDigest
        )
    }

    private func digest(atEntryCount entryCount: UInt64, in ledger: StoredAuditLedger) throws
        -> Data {
        guard entryCount <= UInt64(ledger.entries.count) else {
            throw EncryptedDurableAuditStoreError.rollbackDetected
        }
        guard entryCount > 0 else { return StoredAuditHeadAnchor.empty.headDigest }
        return ledger.entries[Int(entryCount - 1)].digest
    }

    private func mapAnchorError(_ error: AuditHeadAnchorVaultError)
        -> EncryptedDurableAuditStoreError {
        switch error {
        case .invalidStoredAnchor, .missingAnchor:
            return .corruptAnchor
        case .interactionNotAllowed, .authenticationFailed, .unexpectedStatus:
            return .anchorUnavailable
        }
    }

    private func openLedger(
        _ record: EncryptedWorkspaceRecord,
        workspaceID: WorkspaceID
    ) async throws -> StoredAuditLedger {
        guard record.workspaceID == workspaceID,
              record.collection == Self.collection,
              record.id == Self.recordID else {
            throw EncryptedDurableAuditStoreError.corruptLedger
        }
        let plaintext: Data
        do {
            plaintext = try await codec.open(record)
        } catch {
            throw EncryptedDurableAuditStoreError.corruptLedger
        }
        guard plaintext.count <= EncryptedWorkspaceRecordCodec.maximumPlaintextBytes else {
            throw EncryptedDurableAuditStoreError.corruptLedger
        }
        let ledger: StoredAuditLedger
        if let current = try? decoder.decode(StoredAuditLedger.self, from: plaintext),
           current.schemaVersion == Self.schemaVersion,
           (try? encoder.encode(current)) == plaintext {
            ledger = current
        } else if let legacy = try? decoder.decode(LegacyStoredAuditLedger.self, from: plaintext),
                  legacy.schemaVersion == Self.legacySchemaVersion,
                  (try? encoder.encode(legacy)) == plaintext {
            ledger = StoredAuditLedger(
                schemaVersion: Self.schemaVersion,
                workspaceID: legacy.workspaceID,
                generation: 0,
                lifetimeEventCount: UInt64(legacy.entries.count),
                generationBaseEntryCount: 0,
                generationBaseLifetimeEventCount: 0,
                predecessor: nil,
                entries: legacy.entries
            )
        } else {
            throw EncryptedDurableAuditStoreError.corruptLedger
        }
        // Decoding AuditEvent re-applies secret-key redaction. Requiring the
        // canonical re-encoding to match ensures an untrusted writer cannot hide
        // sensitive metadata, duplicate representations, or ignored fields in a
        // decryptable ledger and have them silently retained.
        guard ledger.schemaVersion == Self.schemaVersion,
              ledger.workspaceID == workspaceID,
              ledger.entries.count <= Self.maximumEntries else {
            throw EncryptedDurableAuditStoreError.corruptLedger
        }
        try validateIntegrity(of: ledger)
        return ledger
    }

    private func validateIntegrity(of ledger: StoredAuditLedger) throws {
        guard ledger.schemaVersion == Self.schemaVersion,
              ledger.entries.count <= Self.maximumEntries,
              ledger.generationBaseEntryCount <= UInt64(ledger.entries.count),
              ledger.generationBaseLifetimeEventCount <= ledger.lifetimeEventCount,
              ledger.lifetimeEventCount - ledger.generationBaseLifetimeEventCount
                == UInt64(ledger.entries.count) - ledger.generationBaseEntryCount else {
            throw EncryptedDurableAuditStoreError.corruptLedger
        }
        if ledger.generation == 0 {
            guard ledger.predecessor == nil,
                  ledger.generationBaseEntryCount == 0,
                  ledger.generationBaseLifetimeEventCount == 0 else {
                throw EncryptedDurableAuditStoreError.corruptLedger
            }
        } else {
            guard let predecessor = ledger.predecessor,
                  predecessor.generation < UInt64.max,
                  predecessor.generation + 1 == ledger.generation,
                  predecessor.entryCount <= UInt64(Self.maximumEntries),
                  predecessor.entryCount <= predecessor.lifetimeEventCount,
                  predecessor.headDigest.count == 32,
                  ledger.generationBaseLifetimeEventCount == predecessor.lifetimeEventCount,
                  ledger.generationBaseEntryCount <= predecessor.entryCount else {
                throw EncryptedDurableAuditStoreError.corruptLedger
            }
        }
        var expectedPrevious = Data(repeating: 0, count: 32)
        for (index, entry) in ledger.entries.enumerated() {
            guard entry.sequence == UInt64(index),
                  entry.previousDigest == expectedPrevious,
                  entry.digest.count == 32,
                  entry.event.event.workspaceID == ledger.workspaceID,
                  (try? PersistableAuditEvent(event: entry.event.event)) == entry.event else {
                throw EncryptedDurableAuditStoreError.corruptLedger
            }
            let expectedDigest = try digest(
                workspaceID: ledger.workspaceID,
                sequence: entry.sequence,
                previousDigest: entry.previousDigest,
                event: entry.event
            )
            guard expectedDigest == entry.digest else {
                throw EncryptedDurableAuditStoreError.corruptLedger
            }
            expectedPrevious = entry.digest
        }
    }

    private func digest(
        workspaceID: WorkspaceID,
        sequence: UInt64,
        previousDigest: Data,
        event: PersistableAuditEvent
    ) throws -> Data {
        guard previousDigest.count == 32 else {
            throw EncryptedDurableAuditStoreError.corruptLedger
        }
        let encodedEvent: Data
        do {
            encodedEvent = try encoder.encode(event)
        } catch {
            throw EncryptedDurableAuditStoreError.corruptLedger
        }
        var material = Data("THOX-WR-AUDIT-CHAIN-V1".utf8)
        appendLengthPrefixed(Data(workspaceID.rawValue.uuidString.lowercased().utf8), to: &material)
        var bigEndianSequence = sequence.bigEndian
        withUnsafeBytes(of: &bigEndianSequence) { material.append(contentsOf: $0) }
        appendLengthPrefixed(previousDigest, to: &material)
        appendLengthPrefixed(encodedEvent, to: &material)
        return Data(SHA256.hash(data: material))
    }

    private func appendLengthPrefixed(_ value: Data, to destination: inout Data) {
        var length = UInt64(value.count).bigEndian
        withUnsafeBytes(of: &length) { destination.append(contentsOf: $0) }
        destination.append(value)
    }

    private func cursorOffset(
        _ cursor: AuditEventCursor?,
        in ledger: StoredAuditLedger
    ) throws -> Int {
        guard let cursor else { return 0 }
        let data = cursor.withUnsafeBytes { Data($0) }
        guard let payload = try? decoder.decode(StoredAuditCursor.self, from: data),
              payload.schemaVersion == Self.schemaVersion,
              payload.workspaceID == ledger.workspaceID,
              payload.ledgerGeneration == ledger.generation,
              payload.offset > 0,
              payload.offset <= ledger.entries.count,
              ledger.entries[payload.offset - 1].digest == payload.precedingDigest else {
            throw EncryptedDurableAuditStoreError.invalidCursor
        }
        return payload.offset
    }

    private func makeCursor(offset: Int, ledger: StoredAuditLedger) throws -> AuditEventCursor {
        guard offset > 0, offset <= ledger.entries.count else {
            throw EncryptedDurableAuditStoreError.invalidCursor
        }
        let payload = StoredAuditCursor(
            schemaVersion: Self.schemaVersion,
            workspaceID: ledger.workspaceID,
            ledgerGeneration: ledger.generation,
            offset: offset,
            precedingDigest: ledger.entries[offset - 1].digest
        )
        do {
            return try AuditEventCursor(value: encoder.encode(payload))
        } catch {
            throw EncryptedDurableAuditStoreError.invalidCursor
        }
    }

    private func matches(_ date: Date, query: AuditEventQuery) -> Bool {
        if let lower = query.occurredOnOrAfter, date < lower { return false }
        if let upper = query.occurredBefore, date >= upper { return false }
        return true
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

struct StoredAuditLedger: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let generation: UInt64
    var lifetimeEventCount: UInt64
    let generationBaseEntryCount: UInt64
    let generationBaseLifetimeEventCount: UInt64
    let predecessor: StoredAuditLedgerCommitment?
    var entries: [StoredAuditEntry]
}

struct StoredAuditLedgerCommitment: Codable, Equatable, Sendable {
    let generation: UInt64
    let entryCount: UInt64
    let lifetimeEventCount: UInt64
    let headDigest: Data
}

struct LegacyStoredAuditLedger: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let entries: [StoredAuditEntry]
}

struct StoredAuditEntry: Codable, Equatable, Sendable {
    let sequence: UInt64
    let previousDigest: Data
    let digest: Data
    let event: PersistableAuditEvent
}

struct StoredAuditCursor: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let ledgerGeneration: UInt64
    let offset: Int
    let precedingDigest: Data
}

struct StoredAuditExportDigestPayload: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let workspaceID: WorkspaceID
    let occurredOnOrAfter: Date?
    let occurredBefore: Date?
    let applicationVersion: String
    let ledgerGeneration: UInt64
    let retainedEventCount: Int
    let lifetimeEventCount: UInt64
    let sourceHeadSHA256: String
    let events: [RedactedAuditExportEvent]
    let truncated: Bool
}

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
/// Actor isolation serializes one store instance; this type does not claim a
/// multi-process or cross-instance compare-and-swap boundary.
public actor EncryptedDurableAuditEventStore: DurableAuditEventStore {
    static let schemaVersion = 1
    static let maximumEntries = 10_000
    static let collection = try! WorkspaceDataCollection(validating: "private.audit.v1")
    static let recordID = EncryptedWorkspaceRecordID(
        rawValue: UUID(uuidString: "A7D17000-1ED6-4D1F-AD17-000000000001")!
    )

    private let dataStore: any EncryptedWorkspaceDataStore
    private let codec: EncryptedWorkspaceRecordCodec
    private let anchorVault: any AuditHeadAnchorProviding
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates an audit store in the app container backed by device-only Keychain keys.
    public init() throws {
        dataStore = try EncryptedWorkspaceFileDataStore()
        codec = EncryptedWorkspaceRecordCodec()
        anchorVault = KeychainAuditHeadAnchorVault()
        encoder = Self.makeEncoder()
        decoder = Self.makeDecoder()
    }

    init(
        dataStore: any EncryptedWorkspaceDataStore,
        codec: EncryptedWorkspaceRecordCodec,
        anchorVault: any AuditHeadAnchorProviding
    ) {
        self.dataStore = dataStore
        self.codec = codec
        self.anchorVault = anchorVault
        encoder = Self.makeEncoder()
        decoder = Self.makeDecoder()
    }

    public func append(_ event: PersistableAuditEvent) async throws {
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
        let updatedAt = max(createdAt, Date())
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
        guard ledgerCount >= stored.entryCount else {
            throw EncryptedDurableAuditStoreError.rollbackDetected
        }
        if stored.entryCount == 0 {
            guard stored.headDigest == StoredAuditHeadAnchor.empty.headDigest else {
                throw EncryptedDurableAuditStoreError.corruptAnchor
            }
        } else {
            let anchoredIndex = Int(stored.entryCount - 1)
            guard ledger.entries[anchoredIndex].digest == stored.headDigest else {
                throw EncryptedDurableAuditStoreError.rollbackDetected
            }
        }
        guard ledgerCount > stored.entryCount else { return }

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
                entryCount: UInt64(ledger.entries.count),
                headDigest: digest
            )
        } catch {
            throw EncryptedDurableAuditStoreError.corruptLedger
        }
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
        do {
            ledger = try decoder.decode(StoredAuditLedger.self, from: plaintext)
        } catch {
            throw EncryptedDurableAuditStoreError.corruptLedger
        }
        // Decoding AuditEvent re-applies secret-key redaction. Requiring the
        // canonical re-encoding to match ensures an untrusted writer cannot hide
        // sensitive metadata, duplicate representations, or ignored fields in a
        // decryptable ledger and have them silently retained.
        guard (try? encoder.encode(ledger)) == plaintext else {
            throw EncryptedDurableAuditStoreError.corruptLedger
        }
        guard ledger.schemaVersion == Self.schemaVersion,
              ledger.workspaceID == workspaceID,
              ledger.entries.count <= Self.maximumEntries else {
            throw EncryptedDurableAuditStoreError.corruptLedger
        }
        try validateIntegrity(of: ledger)
        return ledger
    }

    private func validateIntegrity(of ledger: StoredAuditLedger) throws {
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
    var entries: [StoredAuditEntry]
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
    let offset: Int
    let precedingDigest: Data
}

import CryptoKit
import Foundation
import XCTest
@testable import WarRoomAppleInfrastructure
import WarRoomCore

final class EncryptedDurableAuditedOperationStoreTests: XCTestCase {
    func testPersistsEncryptedPendingThenTerminalEvidenceAcrossInstances() async throws {
        let records = OperationMemoryDataStore()
        let keys = OperationMemoryKeyVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: keys)
        let anchors = OperationMemoryAnchorVault()
        let workspaceID = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let correlation = correlationID("10000000-0000-0000-0000-000000000001")
        let first = EncryptedDurableAuditedOperationStore(
            dataStore: records,
            codec: codec,
            anchorVault: anchors
        )

        let intent = try event(
            workspaceID: workspaceID,
            correlationID: correlation,
            action: "intent",
            outcome: .requested,
            sensitiveValue: "never-write-this-credential"
        )
        let appendResult = try await first.appendIntent(intent, correlationID: correlation)
        XCTAssertEqual(appendResult, .appended)

        let storedEnvelope = await records.record(
            id: EncryptedDurableAuditedOperationStore.ledgerRecordID,
            workspaceID: workspaceID
        )
        let envelope = try XCTUnwrap(storedEnvelope)
        let encodedEnvelope = try JSONEncoder().encode(envelope)
        XCTAssertNil(encodedEnvelope.range(of: Data("never-write-this-credential".utf8)))
        XCTAssertNil(encodedEnvelope.range(of: Data("hermes.operation".utf8)))

        let restarted = EncryptedDurableAuditedOperationStore(
            dataStore: records,
            codec: codec,
            anchorVault: anchors
        )
        let pending = try await restarted.reconciliationRecords(matching: .init(
            workspaceID: workspaceID,
            status: .pending
        ))
        XCTAssertEqual(pending.records.map(\.correlationID), [correlation])
        XCTAssertEqual(pending.records.first?.intent.event.metadata["credential"], .redacted)

        try await restarted.appendOutcome(
            event(
                workspaceID: workspaceID,
                correlationID: correlation,
                action: "outcome",
                outcome: .succeeded
            ),
            correlationID: correlation
        )
        let noLongerPending = try await restarted.reconciliationRecords(matching: .init(
            workspaceID: workspaceID,
            status: .pending
        ))
        XCTAssertTrue(noLongerPending.records.isEmpty)
        let terminal = try await restarted.reconciliationRecords(matching: .init(
            workspaceID: workspaceID,
            status: .terminal
        ))
        XCTAssertEqual(terminal.records.map(\.correlationID), [correlation])
        XCTAssertEqual(terminal.records.first?.outcome?.event.outcome, .succeeded)
    }

    func testConcurrentCrossWorkspaceClaimHasExactlyOneWinner() async throws {
        let lockRoot = temporaryDirectory("operation-claim-lock")
        defer { try? FileManager.default.removeItem(at: lockRoot) }
        let records = OperationMemoryDataStore()
        let keys = OperationMemoryKeyVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: keys)
        let anchors = OperationMemoryAnchorVault()
        let firstStore = EncryptedDurableAuditedOperationStore(
            dataStore: records,
            codec: codec,
            anchorVault: anchors,
            lockCoordinator: try AuditWorkspaceLockCoordinator(rootURL: lockRoot)
        )
        let secondStore = EncryptedDurableAuditedOperationStore(
            dataStore: records,
            codec: codec,
            anchorVault: anchors,
            lockCoordinator: try AuditWorkspaceLockCoordinator(rootURL: lockRoot)
        )
        let firstWorkspace = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let secondWorkspace = workspace("BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
        let correlation = correlationID("20000000-0000-0000-0000-000000000001")

        let results = try await withThrowingTaskGroup(
            of: AuditedOperationIntentAppendResult.self
        ) { group in
            group.addTask {
                try await firstStore.appendIntent(
                    self.event(
                        workspaceID: firstWorkspace,
                        correlationID: correlation,
                        action: "intent",
                        outcome: .requested
                    ),
                    correlationID: correlation
                )
            }
            group.addTask {
                try await secondStore.appendIntent(
                    self.event(
                        workspaceID: secondWorkspace,
                        correlationID: correlation,
                        action: "intent",
                        outcome: .requested
                    ),
                    correlationID: correlation
                )
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        XCTAssertEqual(results.filter { $0 == .appended }.count, 1)
        XCTAssertEqual(results.filter { $0 == .replayRejected }.count, 1)
        let firstPending = try await firstStore.reconciliationRecords(matching: .init(
            workspaceID: firstWorkspace,
            status: .pending
        ))
        let secondPending = try await firstStore.reconciliationRecords(matching: .init(
            workspaceID: secondWorkspace,
            status: .pending
        ))
        XCTAssertEqual(firstPending.records.count + secondPending.records.count, 1)
    }

    func testCancelledLockWaiterDoesNotClaimOrPoisonLaterAppend() async throws {
        let lockRoot = temporaryDirectory("operation-cancel-lock")
        defer { try? FileManager.default.removeItem(at: lockRoot) }
        let records = OperationMemoryDataStore()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: OperationMemoryKeyVault())
        let anchors = OperationMemoryAnchorVault()
        let holderCoordinator = try AuditWorkspaceLockCoordinator(rootURL: lockRoot)
        let store = EncryptedDurableAuditedOperationStore(
            dataStore: records,
            codec: codec,
            anchorVault: anchors,
            lockCoordinator: try AuditWorkspaceLockCoordinator(rootURL: lockRoot)
        )
        let entered = expectation(description: "global operation lock acquired")
        let holder = Task {
            try await holderCoordinator.withLock(
                for: EncryptedDurableAuditedOperationStore.globalLockScope
            ) {
                entered.fulfill()
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        await fulfillment(of: [entered], timeout: 1)
        let workspaceID = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let correlation = correlationID("21000000-0000-0000-0000-000000000001")
        let intent = try event(
            workspaceID: workspaceID,
            correlationID: correlation,
            action: "intent",
            outcome: .requested
        )
        let waiter = Task {
            try await store.appendIntent(intent, correlationID: correlation)
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        waiter.cancel()
        do {
            _ = try await waiter.value
            XCTFail("Expected cancelled claim waiter")
        } catch is CancellationError {
            // Expected: no persistence transaction began.
        }
        try await holder.value

        let laterAppend = try await store.appendIntent(intent, correlationID: correlation)
        XCTAssertEqual(laterAppend, .appended)
    }

    func testRejectsMissingCrossWorkspaceAndDuplicateOutcomes() async throws {
        let records = OperationMemoryDataStore()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: OperationMemoryKeyVault())
        let store = EncryptedDurableAuditedOperationStore(
            dataStore: records,
            codec: codec,
            anchorVault: OperationMemoryAnchorVault()
        )
        let firstWorkspace = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let secondWorkspace = workspace("BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
        let correlation = correlationID("30000000-0000-0000-0000-000000000001")
        let missing = correlationID("30000000-0000-0000-0000-000000000002")

        await assertStoreError(.missingIntent) {
            try await store.appendOutcome(
                self.event(
                    workspaceID: firstWorkspace,
                    correlationID: missing,
                    action: "outcome",
                    outcome: .failed
                ),
                correlationID: missing
            )
        }
        _ = try await store.appendIntent(
            event(
                workspaceID: firstWorkspace,
                correlationID: correlation,
                action: "intent",
                outcome: .requested
            ),
            correlationID: correlation
        )
        await assertStoreError(.crossWorkspaceOutcome) {
            try await store.appendOutcome(
                self.event(
                    workspaceID: secondWorkspace,
                    correlationID: correlation,
                    action: "outcome",
                    outcome: .succeeded
                ),
                correlationID: correlation
            )
        }
        let outcome = try event(
            workspaceID: firstWorkspace,
            correlationID: correlation,
            action: "outcome",
            outcome: .succeeded
        )
        try await store.appendOutcome(outcome, correlationID: correlation)
        await assertStoreError(.duplicateOutcome) {
            try await store.appendOutcome(outcome, correlationID: correlation)
        }
    }

    func testCiphertextTamperFailsClosedWithRedactedError() async throws {
        let records = OperationMemoryDataStore()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: OperationMemoryKeyVault())
        let store = EncryptedDurableAuditedOperationStore(
            dataStore: records,
            codec: codec,
            anchorVault: OperationMemoryAnchorVault()
        )
        let workspaceID = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let correlation = correlationID("40000000-0000-0000-0000-000000000001")
        _ = try await store.appendIntent(
            event(
                workspaceID: workspaceID,
                correlationID: correlation,
                action: "intent",
                outcome: .requested
            ),
            correlationID: correlation
        )
        try await records.tamper(
            id: EncryptedDurableAuditedOperationStore.ledgerRecordID,
            workspaceID: workspaceID
        )

        do {
            _ = try await store.reconciliationRecords(matching: .init(
                workspaceID: workspaceID,
                status: .pending
            ))
            XCTFail("Expected authenticated decryption failure")
        } catch {
            XCTAssertEqual(
                error as? EncryptedDurableAuditedOperationStoreError,
                .corruptLedger
            )
            XCTAssertEqual(
                String(describing: error),
                "Encrypted operation evidence is unavailable."
            )
            XCTAssertEqual(
                String(reflecting: error),
                "EncryptedDurableAuditedOperationStoreError(<redacted>)"
            )
        }
    }

    func testCiphertextDeletionAndAuthenticatedRollbackAreRejectedByAnchor() async throws {
        let records = OperationMemoryDataStore()
        let anchors = OperationMemoryAnchorVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: OperationMemoryKeyVault())
        let store = EncryptedDurableAuditedOperationStore(
            dataStore: records,
            codec: codec,
            anchorVault: anchors
        )
        let workspaceID = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let correlation = correlationID("41000000-0000-0000-0000-000000000001")
        _ = try await store.appendIntent(
            event(
                workspaceID: workspaceID,
                correlationID: correlation,
                action: "intent",
                outcome: .requested
            ),
            correlationID: correlation
        )
        let pendingSnapshot = await records.snapshot(
            id: EncryptedDurableAuditedOperationStore.ledgerRecordID,
            workspaceID: workspaceID
        )
        let pendingCiphertext = try XCTUnwrap(pendingSnapshot)
        try await store.appendOutcome(
            event(
                workspaceID: workspaceID,
                correlationID: correlation,
                action: "outcome",
                outcome: .succeeded
            ),
            correlationID: correlation
        )

        await records.restore(pendingCiphertext)
        await assertStoreError(.rollbackDetected) {
            _ = try await store.reconciliationRecords(matching: .init(
                workspaceID: workspaceID,
                status: .pending
            ))
        }

        try await records.deleteRecord(
            id: EncryptedDurableAuditedOperationStore.ledgerRecordID,
            in: workspaceID
        )
        await assertStoreError(.rollbackDetected) {
            _ = try await store.reconciliationRecords(matching: .init(
                workspaceID: workspaceID,
                status: .pending
            ))
        }
    }

    func testRecordAheadOfAnchorRecoversInterruptedCommitAndStillRejectsReplay() async throws {
        let records = OperationMemoryDataStore()
        let anchors = OperationMemoryAnchorVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: OperationMemoryKeyVault())
        let store = EncryptedDurableAuditedOperationStore(
            dataStore: records,
            codec: codec,
            anchorVault: anchors
        )
        let workspaceID = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let correlation = correlationID("42000000-0000-0000-0000-000000000001")
        await anchors.failNextStore()

        await assertStoreError(.anchorUnavailable) {
            _ = try await store.appendIntent(
                self.event(
                    workspaceID: workspaceID,
                    correlationID: correlation,
                    action: "intent",
                    outcome: .requested
                ),
                correlationID: correlation
            )
        }
        let restarted = EncryptedDurableAuditedOperationStore(
            dataStore: records,
            codec: codec,
            anchorVault: anchors
        )
        let recovered = try await restarted.reconciliationRecords(matching: .init(
            workspaceID: workspaceID,
            status: .pending
        ))
        XCTAssertEqual(recovered.records.map(\.correlationID), [correlation])
        let replay = try await restarted.appendIntent(
            event(
                workspaceID: workspaceID,
                correlationID: correlation,
                action: "intent",
                outcome: .requested
            ),
            correlationID: correlation
        )
        XCTAssertEqual(replay, .replayRejected)
    }

    func testReconciliationIsWorkspaceScopedStatusFilteredAndBounded() async throws {
        let records = OperationMemoryDataStore()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: OperationMemoryKeyVault())
        let store = EncryptedDurableAuditedOperationStore(
            dataStore: records,
            codec: codec,
            anchorVault: OperationMemoryAnchorVault()
        )
        let firstWorkspace = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let secondWorkspace = workspace("BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
        let correlations = (1...4).map {
            correlationID(String(format: "50000000-0000-0000-0000-%012d", $0))
        }
        for (index, correlation) in correlations.enumerated() {
            let target = index == 3 ? secondWorkspace : firstWorkspace
            _ = try await store.appendIntent(
                event(
                    workspaceID: target,
                    correlationID: correlation,
                    action: "intent",
                    outcome: .requested,
                    occurredAt: Double(index)
                ),
                correlationID: correlation
            )
        }
        try await store.appendOutcome(
            event(
                workspaceID: firstWorkspace,
                correlationID: correlations[0],
                action: "outcome",
                outcome: .succeeded
            ),
            correlationID: correlations[0]
        )

        let pending = try await store.reconciliationRecords(matching: .init(
            workspaceID: firstWorkspace,
            status: .pending,
            limit: try AuditedOperationReconciliationLimit(rawValue: 1)
        ))
        XCTAssertEqual(pending.records.count, 1)
        XCTAssertTrue(pending.truncated)
        XCTAssertTrue(pending.records.allSatisfy { $0.workspaceID == firstWorkspace })
        let terminal = try await store.reconciliationRecords(matching: .init(
            workspaceID: firstWorkspace,
            status: .terminal
        ))
        XCTAssertEqual(terminal.records.map(\.correlationID), [correlations[0]])
        XCTAssertFalse(terminal.truncated)
    }

    private func assertStoreError(
        _ expected: EncryptedDurableAuditedOperationStoreError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected durable operation store rejection")
        } catch {
            XCTAssertEqual(error as? EncryptedDurableAuditedOperationStoreError, expected)
        }
    }

    private func event(
        workspaceID: WorkspaceID,
        correlationID: AuditedOperationCorrelationID,
        action: String,
        outcome: AuditOutcome,
        sensitiveValue: String? = nil,
        occurredAt: TimeInterval = 100
    ) throws -> PersistableAuditEvent {
        var fields = [
            AuditField(
                key: "correlation_id",
                value: .string(correlationID.description),
                privacy: .nonSensitive
            ),
            AuditField(
                key: "operation",
                value: .string("approval"),
                privacy: .nonSensitive
            ),
        ]
        if let sensitiveValue {
            fields.append(AuditField(
                key: "credential",
                value: .string(sensitiveValue),
                privacy: .sensitive
            ))
        }
        return try PersistableAuditEvent(event: AuditEvent(
            occurredAt: Date(timeIntervalSince1970: occurredAt),
            workspaceID: workspaceID,
            category: "hermes.operation",
            action: action,
            outcome: outcome,
            fields: fields
        ))
    }

    private func workspace(_ value: String) -> WorkspaceID {
        WorkspaceID(rawValue: UUID(uuidString: value)!)
    }

    private func correlationID(_ value: String) -> AuditedOperationCorrelationID {
        AuditedOperationCorrelationID(rawValue: UUID(uuidString: value)!)
    }

    private func temporaryDirectory(_ label: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "thox-\(label)-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
    }
}

private actor OperationMemoryKeyVault: WorkspaceMasterKeyProviding {
    private var keys: [WorkspaceID: SymmetricKey] = [:]

    func masterKey(
        for workspaceID: WorkspaceID,
        createIfMissing: Bool
    ) async throws -> SymmetricKey? {
        if let key = keys[workspaceID] { return key }
        guard createIfMissing else { return nil }
        let key = SymmetricKey(size: .bits256)
        keys[workspaceID] = key
        return key
    }

    func deleteMasterKey(for workspaceID: WorkspaceID) async throws {
        keys.removeValue(forKey: workspaceID)
    }
}

private actor OperationMemoryAnchorVault: OperationStateAnchorProviding {
    private var value: StoredOperationStateAnchor?
    private var shouldFailNextStore = false

    func anchor() async throws -> StoredOperationStateAnchor? { value }

    func initializeEmptyAnchor() async throws -> StoredOperationStateAnchor {
        if let value { return value }
        value = .empty
        return .empty
    }

    func store(_ anchor: StoredOperationStateAnchor) async throws {
        if shouldFailNextStore {
            shouldFailNextStore = false
            throw OperationStateAnchorVaultError.authenticationFailed
        }
        value = anchor
    }

    func failNextStore() {
        shouldFailNextStore = true
    }
}

private actor OperationMemoryDataStore: AuditedOperationWorkspaceDataStore {
    private var stored: [WorkspaceID: [EncryptedWorkspaceRecordID: EncryptedWorkspaceRecord]] = [:]

    func record(
        id: EncryptedWorkspaceRecordID,
        in workspaceID: WorkspaceID
    ) async throws -> EncryptedWorkspaceRecord? {
        stored[workspaceID]?[id]
    }

    func records(
        in workspaceID: WorkspaceID,
        collection: WorkspaceDataCollection,
        limit: WorkspaceDataPageLimit
    ) async throws -> [EncryptedWorkspaceRecord] {
        Array((stored[workspaceID]?.values ?? [:].values)
            .filter { $0.collection == collection }
            .prefix(limit.rawValue))
    }

    func save(_ record: EncryptedWorkspaceRecord) async throws {
        stored[record.workspaceID, default: [:]][record.id] = record
    }

    func deleteRecord(
        id: EncryptedWorkspaceRecordID,
        in workspaceID: WorkspaceID
    ) async throws {
        stored[workspaceID]?.removeValue(forKey: id)
    }

    func workspaceIDs() async throws -> [WorkspaceID] {
        Array(stored.keys)
    }

    func record(
        id: EncryptedWorkspaceRecordID,
        workspaceID: WorkspaceID
    ) -> EncryptedWorkspaceRecord? {
        stored[workspaceID]?[id]
    }

    func tamper(
        id: EncryptedWorkspaceRecordID,
        workspaceID: WorkspaceID
    ) throws {
        guard let record = stored[workspaceID]?[id] else { return }
        var ciphertext = record.ciphertext
        ciphertext[ciphertext.startIndex] ^= 0xff
        stored[workspaceID]?[id] = try EncryptedWorkspaceRecord(
            id: record.id,
            workspaceID: record.workspaceID,
            collection: record.collection,
            algorithm: record.algorithm,
            keyReference: record.keyReference,
            nonce: record.nonce,
            ciphertext: ciphertext,
            authenticationTag: record.authenticationTag,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    func snapshot(
        id: EncryptedWorkspaceRecordID,
        workspaceID: WorkspaceID
    ) -> EncryptedWorkspaceRecord? {
        stored[workspaceID]?[id]
    }

    func restore(_ record: EncryptedWorkspaceRecord) {
        stored[record.workspaceID, default: [:]][record.id] = record
    }
}

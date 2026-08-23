import CryptoKit
import Foundation
import XCTest
@testable import WarRoomAppleInfrastructure
import WarRoomCore

final class EncryptedDurableAuditEventStoreTests: XCTestCase {
    func testAppendIsOrderedIdempotentEncryptedAndWorkspaceIsolated() async throws {
        let records = AuditMemoryEncryptedRecordStore()
        let keys = AuditMemoryMasterKeyVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: keys)
        let store = EncryptedDurableAuditEventStore(
            dataStore: records,
            codec: codec,
            anchorVault: AuditMemoryHeadAnchorVault()
        )
        let firstWorkspace = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let secondWorkspace = workspace("BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
        let first = try event(
            id: "10000000-0000-0000-0000-000000000001",
            workspaceID: firstWorkspace,
            occurredAt: 300,
            action: "first"
        )
        let second = try event(
            id: "10000000-0000-0000-0000-000000000002",
            workspaceID: firstWorkspace,
            occurredAt: 100,
            action: "second"
        )
        let foreign = try event(
            id: "20000000-0000-0000-0000-000000000001",
            workspaceID: secondWorkspace,
            occurredAt: 200,
            action: "foreign"
        )

        try await store.append(first)
        try await store.append(second)
        try await store.append(first)
        try await store.append(foreign)

        let firstPage = try await store.events(matching: AuditEventQuery(workspaceID: firstWorkspace))
        let secondPage = try await store.events(matching: AuditEventQuery(workspaceID: secondWorkspace))
        XCTAssertEqual(firstPage.events, [first, second], "append order must not be timestamp order")
        XCTAssertEqual(secondPage.events, [foreign])
        let saveCount = await records.saveCount(for: firstWorkspace)
        XCTAssertEqual(saveCount, 2)

        let storedEncrypted = await records.storedRecord(
            id: EncryptedDurableAuditEventStore.recordID,
            workspaceID: firstWorkspace
        )
        let encrypted = try XCTUnwrap(storedEncrypted)
        let envelope = try JSONEncoder().encode(encrypted)
        XCTAssertFalse(envelope.contains(Data("first".utf8)))
        XCTAssertFalse(envelope.contains(Data("second".utf8)))
    }

    func testConflictingDuplicateIdentifierFailsClosedWithRedactedError() async throws {
        let (store, _, _) = makeStore()
        let workspaceID = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let identifier = "10000000-0000-0000-0000-000000000001"
        try await store.append(try event(
            id: identifier,
            workspaceID: workspaceID,
            occurredAt: 100,
            action: "original"
        ))

        do {
            try await store.append(try event(
                id: identifier,
                workspaceID: workspaceID,
                occurredAt: 100,
                action: "replacement"
            ))
            XCTFail("Expected conflicting identifier rejection")
        } catch {
            XCTAssertEqual(
                error as? EncryptedDurableAuditStoreError,
                .conflictingEventIdentifier
            )
            XCTAssertEqual(String(describing: error), "Encrypted audit history is unavailable.")
            XCTAssertFalse(String(reflecting: error).contains("replacement"))
        }
    }

    func testBoundedPagingTimeFilterAndCursorWorkspaceBinding() async throws {
        let (store, _, _) = makeStore()
        let firstWorkspace = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let secondWorkspace = workspace("BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
        for index in 0..<5 {
            try await store.append(try event(
                id: String(format: "10000000-0000-0000-0000-%012d", index),
                workspaceID: firstWorkspace,
                occurredAt: Double(index * 10),
                action: "action-\(index)"
            ))
        }

        let initial = try await store.events(matching: AuditEventQuery(
            workspaceID: firstWorkspace,
            occurredOnOrAfter: Date(timeIntervalSince1970: 10),
            occurredBefore: Date(timeIntervalSince1970: 50),
            limit: try AuditEventPageLimit(rawValue: 2)
        ))
        XCTAssertEqual(initial.events.map(\.event.action), ["action-1", "action-2"])
        let cursor = try XCTUnwrap(initial.nextCursor)

        let continued = try await store.events(matching: AuditEventQuery(
            workspaceID: firstWorkspace,
            occurredOnOrAfter: Date(timeIntervalSince1970: 10),
            occurredBefore: Date(timeIntervalSince1970: 50),
            after: cursor,
            limit: try AuditEventPageLimit(rawValue: 2)
        ))
        XCTAssertEqual(continued.events.map(\.event.action), ["action-3", "action-4"])
        XCTAssertNil(continued.nextCursor)

        do {
            _ = try await store.events(matching: AuditEventQuery(
                workspaceID: secondWorkspace,
                after: cursor
            ))
            XCTFail("Expected cross-workspace cursor rejection")
        } catch {
            XCTAssertEqual(error as? EncryptedDurableAuditStoreError, .invalidCursor)
        }
    }

    func testAuthenticatedCiphertextAndInternalChainTamperingFailClosed() async throws {
        let records = AuditMemoryEncryptedRecordStore()
        let keys = AuditMemoryMasterKeyVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: keys)
        let store = EncryptedDurableAuditEventStore(
            dataStore: records,
            codec: codec,
            anchorVault: AuditMemoryHeadAnchorVault()
        )
        let workspaceID = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        try await store.append(try event(
            id: "10000000-0000-0000-0000-000000000001",
            workspaceID: workspaceID,
            occurredAt: 100,
            action: "first"
        ))
        try await store.append(try event(
            id: "10000000-0000-0000-0000-000000000002",
            workspaceID: workspaceID,
            occurredAt: 200,
            action: "second"
        ))
        let storedOriginal = await records.storedRecord(
            id: EncryptedDurableAuditEventStore.recordID,
            workspaceID: workspaceID
        )
        let original = try XCTUnwrap(storedOriginal)

        var tamperedCiphertext = original.ciphertext
        tamperedCiphertext[tamperedCiphertext.startIndex] ^= 0xff
        await records.replace(try copy(original, ciphertext: tamperedCiphertext))
        await assertCorrupt(store: store, workspaceID: workspaceID)

        await records.replace(original)
        let plaintext = try await codec.open(original)
        let decoder = ledgerDecoder()
        var ledger = try decoder.decode(StoredAuditLedger.self, from: plaintext)
        ledger.entries[1] = StoredAuditEntry(
            sequence: 7,
            previousDigest: ledger.entries[1].previousDigest,
            digest: ledger.entries[1].digest,
            event: ledger.entries[1].event
        )
        let forgedPlaintext = try ledgerEncoder().encode(ledger)
        let forgedRecord = try await codec.seal(
            forgedPlaintext,
            workspaceID: workspaceID,
            collection: EncryptedDurableAuditEventStore.collection,
            recordID: EncryptedDurableAuditEventStore.recordID,
            createdAt: original.createdAt,
            updatedAt: max(original.createdAt, Date())
        )
        await records.replace(forgedRecord)
        await assertCorrupt(store: store, workspaceID: workspaceID)
    }

    func testMissingKeyForExistingCiphertextNeverRegeneratesKey() async throws {
        let (store, _, keys) = makeStore()
        let workspaceID = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        try await store.append(try event(
            id: "10000000-0000-0000-0000-000000000001",
            workspaceID: workspaceID,
            occurredAt: 100,
            action: "first"
        ))
        let initialCreationCount = await keys.creationCount
        XCTAssertEqual(initialCreationCount, 1)
        await keys.deleteMasterKey(for: workspaceID)

        do {
            try await store.append(try event(
                id: "10000000-0000-0000-0000-000000000002",
                workspaceID: workspaceID,
                occurredAt: 200,
                action: "second"
            ))
            XCTFail("Expected unreadable existing ledger")
        } catch {
            XCTAssertEqual(error as? EncryptedDurableAuditStoreError, .corruptLedger)
        }
        let finalCreationCount = await keys.creationCount
        XCTAssertEqual(finalCreationCount, 1)
    }

    func testDecodedSensitiveMetadataCannotBypassRedactionBoundary() async throws {
        let records = AuditMemoryEncryptedRecordStore()
        let keys = AuditMemoryMasterKeyVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: keys)
        let store = EncryptedDurableAuditEventStore(
            dataStore: records,
            codec: codec,
            anchorVault: AuditMemoryHeadAnchorVault()
        )
        let workspaceID = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        try await store.append(try event(
            id: "10000000-0000-0000-0000-000000000001",
            workspaceID: workspaceID,
            occurredAt: 100,
            action: "first"
        ))
        let stored = await records.storedRecord(
            id: EncryptedDurableAuditEventStore.recordID,
            workspaceID: workspaceID
        )
        let original = try XCTUnwrap(stored)
        let canonicalPlaintext = try await codec.open(original)
        let redacted = Data("\"token\":{\"type\":\"redacted\"}".utf8)
        let injected = Data(
            "\"token\":{\"string\":\"private-token-value\",\"type\":\"string\"}".utf8
        )
        guard let range = canonicalPlaintext.range(of: redacted) else {
            return XCTFail("Expected canonical redacted metadata")
        }
        var maliciousPlaintext = canonicalPlaintext
        maliciousPlaintext.replaceSubrange(range, with: injected)
        let maliciousRecord = try await codec.seal(
            maliciousPlaintext,
            workspaceID: workspaceID,
            collection: EncryptedDurableAuditEventStore.collection,
            recordID: EncryptedDurableAuditEventStore.recordID,
            createdAt: original.createdAt,
            updatedAt: max(original.createdAt, Date())
        )
        await records.replace(maliciousRecord)

        await assertCorrupt(store: store, workspaceID: workspaceID)
    }

    func testExistingCiphertextWithoutAnchorFailsClosed() async throws {
        let records = AuditMemoryEncryptedRecordStore()
        let keys = AuditMemoryMasterKeyVault()
        let anchors = AuditMemoryHeadAnchorVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: keys)
        let store = EncryptedDurableAuditEventStore(
            dataStore: records,
            codec: codec,
            anchorVault: anchors
        )
        let workspaceID = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        try await store.append(try event(
            id: "10000000-0000-0000-0000-000000000001",
            workspaceID: workspaceID,
            occurredAt: 100,
            action: "first"
        ))
        await anchors.removeAnchor(for: workspaceID)

        await assertStoreError(.corruptAnchor, store: store, workspaceID: workspaceID)
    }

    func testOlderAuthenticatedCiphertextBehindAnchorIsRejectedAsRollback() async throws {
        let records = AuditMemoryEncryptedRecordStore()
        let keys = AuditMemoryMasterKeyVault()
        let anchors = AuditMemoryHeadAnchorVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: keys)
        let store = EncryptedDurableAuditEventStore(
            dataStore: records,
            codec: codec,
            anchorVault: anchors
        )
        let workspaceID = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        try await store.append(try event(
            id: "10000000-0000-0000-0000-000000000001",
            workspaceID: workspaceID,
            occurredAt: 100,
            action: "first"
        ))
        let storedOlder = await records.storedRecord(
            id: EncryptedDurableAuditEventStore.recordID,
            workspaceID: workspaceID
        )
        let older = try XCTUnwrap(storedOlder)
        try await store.append(try event(
            id: "10000000-0000-0000-0000-000000000002",
            workspaceID: workspaceID,
            occurredAt: 200,
            action: "second"
        ))

        await records.replace(older)
        await assertStoreError(.rollbackDetected, store: store, workspaceID: workspaceID)
    }

    func testAuthenticatedLedgerWithMismatchedAnchoredPrefixIsRejected() async throws {
        let primaryRecords = AuditMemoryEncryptedRecordStore()
        let alternateRecords = AuditMemoryEncryptedRecordStore()
        let keys = AuditMemoryMasterKeyVault()
        let primaryAnchors = AuditMemoryHeadAnchorVault()
        let alternateAnchors = AuditMemoryHeadAnchorVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: keys)
        let primary = EncryptedDurableAuditEventStore(
            dataStore: primaryRecords,
            codec: codec,
            anchorVault: primaryAnchors
        )
        let alternate = EncryptedDurableAuditEventStore(
            dataStore: alternateRecords,
            codec: codec,
            anchorVault: alternateAnchors
        )
        let workspaceID = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        try await primary.append(try event(
            id: "10000000-0000-0000-0000-000000000001",
            workspaceID: workspaceID,
            occurredAt: 100,
            action: "anchored-primary"
        ))
        try await alternate.append(try event(
            id: "20000000-0000-0000-0000-000000000001",
            workspaceID: workspaceID,
            occurredAt: 100,
            action: "divergent-first"
        ))
        try await alternate.append(try event(
            id: "20000000-0000-0000-0000-000000000002",
            workspaceID: workspaceID,
            occurredAt: 200,
            action: "divergent-second"
        ))
        let storedAlternate = await alternateRecords.storedRecord(
            id: EncryptedDurableAuditEventStore.recordID,
            workspaceID: workspaceID
        )
        await primaryRecords.replace(try XCTUnwrap(storedAlternate))

        await assertStoreError(.rollbackDetected, store: primary, workspaceID: workspaceID)
    }

    func testEmptyAnchorExistsBeforeFirstCiphertextSave() async throws {
        let anchors = AuditMemoryHeadAnchorVault()
        let records = AuditMemoryEncryptedRecordStore(anchorObservedAtSave: anchors)
        let keys = AuditMemoryMasterKeyVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: keys)
        let store = EncryptedDurableAuditEventStore(
            dataStore: records,
            codec: codec,
            anchorVault: anchors
        )
        let workspaceID = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")

        try await store.append(try event(
            id: "10000000-0000-0000-0000-000000000001",
            workspaceID: workspaceID,
            occurredAt: 100,
            action: "first"
        ))

        let observed = await records.anchorSeenAtFirstSave()
        XCTAssertEqual(observed, .empty)
    }

    func testAuthenticatedLedgerAheadOfAnchorRecoversCrashAndAdvancesAnchor() async throws {
        let records = AuditMemoryEncryptedRecordStore()
        let keys = AuditMemoryMasterKeyVault()
        let anchors = AuditMemoryHeadAnchorVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: keys)
        let store = EncryptedDurableAuditEventStore(
            dataStore: records,
            codec: codec,
            anchorVault: anchors
        )
        let workspaceID = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        await anchors.failNextStore(with: .interactionNotAllowed)

        do {
            try await store.append(try event(
                id: "10000000-0000-0000-0000-000000000001",
                workspaceID: workspaceID,
                occurredAt: 100,
                action: "survived-crash"
            ))
            XCTFail("Expected simulated post-ciphertext anchor failure")
        } catch {
            XCTAssertEqual(error as? EncryptedDurableAuditStoreError, .anchorUnavailable)
            XCTAssertEqual(String(describing: error), "Encrypted audit history is unavailable.")
        }
        let beforeRecovery = await anchors.storedAnchor(for: workspaceID)
        XCTAssertEqual(beforeRecovery, .empty)

        let recoveredStore = EncryptedDurableAuditEventStore(
            dataStore: records,
            codec: codec,
            anchorVault: anchors
        )
        let page = try await recoveredStore.events(matching: AuditEventQuery(
            workspaceID: workspaceID
        ))
        XCTAssertEqual(page.events.map(\.event.action), ["survived-crash"])
        let storedRecoveredAnchor = await anchors.storedAnchor(for: workspaceID)
        let recoveredAnchor = try XCTUnwrap(storedRecoveredAnchor)
        XCTAssertEqual(recoveredAnchor.entryCount, 1)
        XCTAssertNotEqual(recoveredAnchor.headDigest, StoredAuditHeadAnchor.empty.headDigest)
    }

    func testAnchorReadFailureFailsClosedWithoutLeakingKeychainDetails() async throws {
        let records = AuditMemoryEncryptedRecordStore()
        let keys = AuditMemoryMasterKeyVault()
        let anchors = AuditMemoryHeadAnchorVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: keys)
        let store = EncryptedDurableAuditEventStore(
            dataStore: records,
            codec: codec,
            anchorVault: anchors
        )
        let workspaceID = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        try await store.append(try event(
            id: "10000000-0000-0000-0000-000000000001",
            workspaceID: workspaceID,
            occurredAt: 100,
            action: "first"
        ))
        await anchors.failReads(with: .authenticationFailed)

        do {
            _ = try await store.events(matching: AuditEventQuery(workspaceID: workspaceID))
            XCTFail("Expected fail-closed anchor read")
        } catch {
            XCTAssertEqual(error as? EncryptedDurableAuditStoreError, .anchorUnavailable)
            XCTAssertEqual(String(describing: error), "Encrypted audit history is unavailable.")
            XCTAssertEqual(String(reflecting: error), "EncryptedDurableAuditStoreError(<redacted>)")
        }
    }

    func testConcurrentAppendsAcrossStoreInstancesPreserveEveryEvent() async throws {
        let lockRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "thox-audit-race-\(UUID().uuidString.lowercased())"
        )
        defer { try? FileManager.default.removeItem(at: lockRoot) }
        let records = AuditMemoryEncryptedRecordStore()
        let keys = AuditMemoryMasterKeyVault()
        let anchors = AuditMemoryHeadAnchorVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: keys)
        let firstStore = EncryptedDurableAuditEventStore(
            dataStore: records,
            codec: codec,
            anchorVault: anchors,
            lockCoordinator: try AuditWorkspaceLockCoordinator(rootURL: lockRoot)
        )
        let secondStore = EncryptedDurableAuditEventStore(
            dataStore: records,
            codec: codec,
            anchorVault: anchors,
            lockCoordinator: try AuditWorkspaceLockCoordinator(rootURL: lockRoot)
        )
        let workspaceID = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let expectedCount = 40

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<expectedCount {
                let event = try event(
                    id: String(format: "30000000-0000-0000-0000-%012d", index),
                    workspaceID: workspaceID,
                    occurredAt: Double(index),
                    action: "concurrent-\(index)"
                )
                group.addTask {
                    let target = index.isMultiple(of: 2) ? firstStore : secondStore
                    try await target.append(event)
                }
            }
            try await group.waitForAll()
        }

        let page = try await firstStore.events(matching: AuditEventQuery(
            workspaceID: workspaceID,
            limit: try AuditEventPageLimit(rawValue: expectedCount)
        ))
        XCTAssertEqual(page.events.count, expectedCount)
        XCTAssertEqual(Set(page.events.map(\.event.id)).count, expectedCount)
        let storedAnchor = await anchors.storedAnchor(for: workspaceID)
        let anchor = try XCTUnwrap(storedAnchor)
        XCTAssertEqual(anchor.entryCount, UInt64(expectedCount))
    }

    func testLockContentionFailsStoreClosedBeforeLedgerOrAnchorMutation() async throws {
        let lockRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "thox-audit-lock-failure-\(UUID().uuidString.lowercased())"
        )
        defer { try? FileManager.default.removeItem(at: lockRoot) }
        let records = AuditMemoryEncryptedRecordStore()
        let keys = AuditMemoryMasterKeyVault()
        let anchors = AuditMemoryHeadAnchorVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: keys)
        let workspaceID = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let holderCoordinator = try AuditWorkspaceLockCoordinator(
            rootURL: lockRoot,
            useProcessRegistry: false
        )
        let storeCoordinator = try AuditWorkspaceLockCoordinator(
            rootURL: lockRoot,
            policy: AuditWorkspaceLockPolicy(
                acquisitionTimeoutNanoseconds: 40_000_000,
                pollIntervalNanoseconds: 2_000_000
            ),
            useProcessRegistry: false
        )
        let store = EncryptedDurableAuditEventStore(
            dataStore: records,
            codec: codec,
            anchorVault: anchors,
            lockCoordinator: storeCoordinator
        )
        let entered = expectation(description: "external owner acquired lock")
        let holder = Task {
            try await holderCoordinator.withLock(for: workspaceID) {
                entered.fulfill()
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        await fulfillment(of: [entered], timeout: 1)

        do {
            try await store.append(try event(
                id: "10000000-0000-0000-0000-000000000001",
                workspaceID: workspaceID,
                occurredAt: 100,
                action: "must-not-start"
            ))
            XCTFail("Expected fail-closed store lock timeout")
        } catch {
            XCTAssertEqual(error as? EncryptedDurableAuditStoreError, .lockUnavailable)
            XCTAssertEqual(String(reflecting: error), "EncryptedDurableAuditStoreError(<redacted>)")
        }
        let storedRecord = await records.storedRecord(
            id: EncryptedDurableAuditEventStore.recordID,
            workspaceID: workspaceID
        )
        let storedAnchor = await anchors.storedAnchor(for: workspaceID)
        XCTAssertNil(storedRecord)
        XCTAssertNil(storedAnchor)
        try await holder.value
    }

    func testRetentionPrunesExpiredEventsAcrossAppendOrderAndRejectsPrePruneReplay() async throws {
        let records = AuditMemoryEncryptedRecordStore()
        let keys = AuditMemoryMasterKeyVault()
        let anchors = AuditMemoryHeadAnchorVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: keys)
        let store = EncryptedDurableAuditEventStore(
            dataStore: records,
            codec: codec,
            anchorVault: anchors
        )
        let workspaceID = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let asOf = Date(timeIntervalSince1970: 10_000_000)
        let day: Double = 86_400
        try await store.append(try event(
            id: "40000000-0000-0000-0000-000000000001",
            workspaceID: workspaceID,
            occurredAt: asOf.timeIntervalSince1970 - 40 * day,
            action: "old-first"
        ))
        try await store.append(try event(
            id: "40000000-0000-0000-0000-000000000002",
            workspaceID: workspaceID,
            occurredAt: asOf.timeIntervalSince1970 - 10 * day,
            action: "retained-middle"
        ))
        try await store.append(try event(
            id: "40000000-0000-0000-0000-000000000003",
            workspaceID: workspaceID,
            occurredAt: asOf.timeIntervalSince1970 - 35 * day,
            action: "old-last"
        ))
        let storedPrePruneRecord = await records.storedRecord(
            id: EncryptedDurableAuditEventStore.recordID,
            workspaceID: workspaceID
        )
        let prePruneRecord = try XCTUnwrap(storedPrePruneRecord)

        let result = try await store.applyRetention(
            .finite(try AuditRetentionDays(rawValue: 30)),
            to: workspaceID,
            asOf: asOf
        )

        XCTAssertEqual(result.prunedEventCount, 2)
        XCTAssertEqual(result.retainedEventCount, 1)
        XCTAssertEqual(result.lifetimeEventCount, 3)
        let page = try await store.events(matching: AuditEventQuery(workspaceID: workspaceID))
        XCTAssertEqual(page.events.map(\.event.action), ["retained-middle"])
        try await store.append(try event(
            id: "40000000-0000-0000-0000-000000000004",
            workspaceID: workspaceID,
            occurredAt: asOf.timeIntervalSince1970,
            action: "post-retention"
        ))
        let continued = try await store.events(matching: AuditEventQuery(workspaceID: workspaceID))
        XCTAssertEqual(
            continued.events.map(\.event.action),
            ["retained-middle", "post-retention"]
        )
        let storedAnchor = await anchors.storedAnchor(for: workspaceID)
        let anchor = try XCTUnwrap(storedAnchor)
        XCTAssertEqual(anchor.ledgerGeneration, 1)
        XCTAssertEqual(anchor.entryCount, 2)
        XCTAssertEqual(anchor.lifetimeEventCount, 4)

        await records.replace(prePruneRecord)
        await assertStoreError(.rollbackDetected, store: store, workspaceID: workspaceID)
    }

    func testRetentionRecoversRecordAheadOfAnchorAfterInjectedAnchorFailure() async throws {
        let records = AuditMemoryEncryptedRecordStore()
        let keys = AuditMemoryMasterKeyVault()
        let anchors = AuditMemoryHeadAnchorVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: keys)
        let store = EncryptedDurableAuditEventStore(
            dataStore: records,
            codec: codec,
            anchorVault: anchors
        )
        let workspaceID = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let asOf = Date(timeIntervalSince1970: 10_000_000)
        try await store.append(try event(
            id: "40000000-0000-0000-0000-000000000001",
            workspaceID: workspaceID,
            occurredAt: asOf.timeIntervalSince1970 - 40 * 86_400,
            action: "expired"
        ))
        try await store.append(try event(
            id: "40000000-0000-0000-0000-000000000002",
            workspaceID: workspaceID,
            occurredAt: asOf.timeIntervalSince1970 - 5 * 86_400,
            action: "retained"
        ))
        await anchors.failNextStore(with: .interactionNotAllowed)

        do {
            _ = try await store.applyRetention(
                .finite(try AuditRetentionDays(rawValue: 30)),
                to: workspaceID,
                asOf: asOf
            )
            XCTFail("Expected post-ciphertext anchor failure")
        } catch {
            XCTAssertEqual(error as? EncryptedDurableAuditStoreError, .anchorUnavailable)
        }
        let storedStaleAnchor = await anchors.storedAnchor(for: workspaceID)
        let staleAnchor = try XCTUnwrap(storedStaleAnchor)
        XCTAssertEqual(staleAnchor.ledgerGeneration, 0)

        let recovered = EncryptedDurableAuditEventStore(
            dataStore: records,
            codec: codec,
            anchorVault: anchors
        )
        let page = try await recovered.events(matching: AuditEventQuery(workspaceID: workspaceID))
        XCTAssertEqual(page.events.map(\.event.action), ["retained"])
        let storedAdvancedAnchor = await anchors.storedAnchor(for: workspaceID)
        let advanced = try XCTUnwrap(storedAdvancedAnchor)
        XCTAssertEqual(advanced.ledgerGeneration, 1)
        XCTAssertEqual(advanced.lifetimeEventCount, 2)
    }

    func testRetentionSaveFailureLeavesPriorLedgerAndAnchorIntact() async throws {
        let records = AuditMemoryEncryptedRecordStore()
        let keys = AuditMemoryMasterKeyVault()
        let anchors = AuditMemoryHeadAnchorVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: keys)
        let store = EncryptedDurableAuditEventStore(
            dataStore: records,
            codec: codec,
            anchorVault: anchors
        )
        let workspaceID = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let asOf = Date(timeIntervalSince1970: 10_000_000)
        try await store.append(try event(
            id: "40000000-0000-0000-0000-000000000001",
            workspaceID: workspaceID,
            occurredAt: asOf.timeIntervalSince1970 - 40 * 86_400,
            action: "expired"
        ))
        let priorAnchor = await anchors.storedAnchor(for: workspaceID)
        await records.failNextSave()

        do {
            _ = try await store.applyRetention(
                .finite(try AuditRetentionDays(rawValue: 30)),
                to: workspaceID,
                asOf: asOf
            )
            XCTFail("Expected injected record save failure")
        } catch {
            XCTAssertEqual(error as? EncryptedDurableAuditStoreError, .storageUnavailable)
        }
        let page = try await store.events(matching: AuditEventQuery(workspaceID: workspaceID))
        XCTAssertEqual(page.events.map(\.event.action), ["expired"])
        let finalAnchor = await anchors.storedAnchor(for: workspaceID)
        XCTAssertEqual(finalAnchor, priorAnchor)
    }

    func testIndefiniteRetentionVerifiesWithoutRewritingLedger() async throws {
        let (store, records, _) = makeStore()
        let workspaceID = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        try await store.append(try event(
            id: "40000000-0000-0000-0000-000000000001",
            workspaceID: workspaceID,
            occurredAt: 100,
            action: "kept"
        ))
        let savesBefore = await records.saveCount(for: workspaceID)

        let result = try await store.applyRetention(.indefinite, to: workspaceID)

        XCTAssertNil(result.cutoff)
        XCTAssertEqual(result.prunedEventCount, 0)
        let savesAfter = await records.saveCount(for: workspaceID)
        XCTAssertEqual(savesAfter, savesBefore)
    }

    func testExportIsBoundedIntegrityCommittedAndRemovesStringsPathsAndSecrets() async throws {
        let records = AuditMemoryEncryptedRecordStore()
        let keys = AuditMemoryMasterKeyVault()
        let anchors = AuditMemoryHeadAnchorVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: keys)
        let store = EncryptedDurableAuditEventStore(
            dataStore: records,
            codec: codec,
            anchorVault: anchors
        )
        let workspaceID = workspace("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let first = try PersistableAuditEvent(event: AuditEvent(
            id: AuditEventID(rawValue: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!),
            occurredAt: Date(timeIntervalSince1970: 100),
            workspaceID: workspaceID,
            category: "workspace/export",
            action: "read",
            outcome: .succeeded,
            fields: [
                AuditField(key: "token", value: .string("private-token"), privacy: .sensitive),
                AuditField(key: "path", value: .string("/Users/private/document.txt"), privacy: .nonSensitive),
                AuditField(key: "boundary", value: .string("localMachine"), privacy: .nonSensitive),
                AuditField(key: "count", value: .integer(7), privacy: .nonSensitive),
            ]
        ))
        try await store.append(first)
        try await store.append(try event(
            id: "50000000-0000-0000-0000-000000000002",
            workspaceID: workspaceID,
            occurredAt: 200,
            action: "second"
        ))
        let saveCount = await records.saveCount(for: workspaceID)
        let generatedAt = Date(timeIntervalSince1970: 300)
        let request = try AuditExportRequest(
            workspaceID: workspaceID,
            occurredOnOrAfter: Date(timeIntervalSince1970: 50),
            occurredBefore: Date(timeIntervalSince1970: 250),
            applicationVersion: "1.2.3+45",
            limit: try AuditExportLimit(rawValue: 1)
        )

        let snapshot = try await store.exportSnapshot(request, generatedAt: generatedAt)

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.generatedAt, generatedAt)
        XCTAssertEqual(snapshot.applicationVersion, "1.2.3+45")
        XCTAssertEqual(snapshot.events.count, 1)
        XCTAssertTrue(snapshot.truncated)
        XCTAssertEqual(snapshot.events[0].category, "<redacted>")
        XCTAssertEqual(snapshot.events[0].metadata["token"], .redacted)
        XCTAssertEqual(snapshot.events[0].metadata["path"], .redacted)
        XCTAssertEqual(snapshot.events[0].metadata["boundary"], .redacted)
        XCTAssertEqual(snapshot.events[0].metadata["count"], .integer(7))
        XCTAssertEqual(snapshot.integrity.retainedEventCount, 2)
        XCTAssertEqual(snapshot.integrity.lifetimeEventCount, 2)
        let savesAfter = await records.saveCount(for: workspaceID)
        XCTAssertEqual(savesAfter, saveCount)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let encoded = try encoder.encode(snapshot)
        XCTAssertLessThanOrEqual(encoded.count, RedactedAuditExportSnapshot.maximumEncodedBytes)
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(text.contains("private-token"))
        XCTAssertFalse(text.contains("/Users/private"))
        XCTAssertFalse(text.contains("localMachine"))
        XCTAssertFalse(text.contains("ciphertext"))
        XCTAssertFalse(text.contains("keyReference"))
        XCTAssertFalse(text.contains("authenticationTag"))
    }

    private func makeStore() -> (
        EncryptedDurableAuditEventStore,
        AuditMemoryEncryptedRecordStore,
        AuditMemoryMasterKeyVault
    ) {
        let records = AuditMemoryEncryptedRecordStore()
        let keys = AuditMemoryMasterKeyVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: keys)
        return (
            EncryptedDurableAuditEventStore(
                dataStore: records,
                codec: codec,
                anchorVault: AuditMemoryHeadAnchorVault()
            ),
            records,
            keys
        )
    }

    private func event(
        id: String,
        workspaceID: WorkspaceID,
        occurredAt: Double,
        action: String
    ) throws -> PersistableAuditEvent {
        try PersistableAuditEvent(event: AuditEvent(
            id: AuditEventID(rawValue: UUID(uuidString: id)!),
            occurredAt: Date(timeIntervalSince1970: occurredAt),
            workspaceID: workspaceID,
            category: "workspace",
            action: action,
            outcome: .succeeded,
            fields: [
                AuditField(key: "token", value: .string("must-not-persist"), privacy: .nonSensitive),
                AuditField(key: "boundary", value: .string("localMachine"), privacy: .nonSensitive),
            ]
        ))
    }

    private func workspace(_ value: String) -> WorkspaceID {
        WorkspaceID(rawValue: UUID(uuidString: value)!)
    }

    private func assertCorrupt(
        store: EncryptedDurableAuditEventStore,
        workspaceID: WorkspaceID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await store.events(matching: AuditEventQuery(workspaceID: workspaceID))
            XCTFail("Expected corrupt ledger rejection", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? EncryptedDurableAuditStoreError,
                .corruptLedger,
                file: file,
                line: line
            )
        }
    }

    private func assertStoreError(
        _ expected: EncryptedDurableAuditStoreError,
        store: EncryptedDurableAuditEventStore,
        workspaceID: WorkspaceID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await store.events(matching: AuditEventQuery(workspaceID: workspaceID))
            XCTFail("Expected audit-store rejection", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? EncryptedDurableAuditStoreError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func copy(
        _ record: EncryptedWorkspaceRecord,
        ciphertext: Data
    ) throws -> EncryptedWorkspaceRecord {
        try EncryptedWorkspaceRecord(
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

    private func ledgerEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private func ledgerDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

private actor AuditMemoryHeadAnchorVault: AuditHeadAnchorProviding {
    private var values: [WorkspaceID: StoredAuditHeadAnchor] = [:]
    private var nextStoreError: AuditHeadAnchorVaultError?
    private var readError: AuditHeadAnchorVaultError?

    func anchor(for workspaceID: WorkspaceID) throws -> StoredAuditHeadAnchor? {
        if let readError { throw readError }
        return values[workspaceID]
    }

    func initializeEmptyAnchor(for workspaceID: WorkspaceID) throws
        -> StoredAuditHeadAnchor {
        if let readError { throw readError }
        if let existing = values[workspaceID] { return existing }
        values[workspaceID] = .empty
        return .empty
    }

    func store(_ anchor: StoredAuditHeadAnchor, for workspaceID: WorkspaceID) throws {
        if let nextStoreError {
            self.nextStoreError = nil
            throw nextStoreError
        }
        guard values[workspaceID] != nil else {
            throw AuditHeadAnchorVaultError.missingAnchor
        }
        values[workspaceID] = anchor
    }

    func storedAnchor(for workspaceID: WorkspaceID) -> StoredAuditHeadAnchor? {
        values[workspaceID]
    }

    func removeAnchor(for workspaceID: WorkspaceID) {
        values[workspaceID] = nil
    }

    func failNextStore(with error: AuditHeadAnchorVaultError) {
        nextStoreError = error
    }

    func failReads(with error: AuditHeadAnchorVaultError) {
        readError = error
    }
}

private actor AuditMemoryEncryptedRecordStore: EncryptedWorkspaceDataStore {
    private var values: [WorkspaceID: [EncryptedWorkspaceRecordID: EncryptedWorkspaceRecord]] = [:]
    private var saves: [WorkspaceID: Int] = [:]
    private let anchorObservedAtSave: AuditMemoryHeadAnchorVault?
    private var firstSaveAnchor: StoredAuditHeadAnchor?
    private var shouldFailNextSave = false

    init(anchorObservedAtSave: AuditMemoryHeadAnchorVault? = nil) {
        self.anchorObservedAtSave = anchorObservedAtSave
    }

    func record(
        id: EncryptedWorkspaceRecordID,
        in workspaceID: WorkspaceID
    ) -> EncryptedWorkspaceRecord? {
        values[workspaceID]?[id]
    }

    func records(
        in workspaceID: WorkspaceID,
        collection: WorkspaceDataCollection,
        limit: WorkspaceDataPageLimit
    ) -> [EncryptedWorkspaceRecord] {
        Array(values[workspaceID, default: [:]].values
            .filter { $0.collection == collection }
            .prefix(limit.rawValue))
    }

    func save(_ record: EncryptedWorkspaceRecord) async throws {
        if shouldFailNextSave {
            shouldFailNextSave = false
            throw AuditInjectedFailure.save
        }
        if firstSaveAnchor == nil, let anchorObservedAtSave {
            firstSaveAnchor = try? await anchorObservedAtSave.anchor(for: record.workspaceID)
        }
        values[record.workspaceID, default: [:]][record.id] = record
        saves[record.workspaceID, default: 0] += 1
    }

    func deleteRecord(id: EncryptedWorkspaceRecordID, in workspaceID: WorkspaceID) {
        values[workspaceID]?[id] = nil
    }

    func storedRecord(
        id: EncryptedWorkspaceRecordID,
        workspaceID: WorkspaceID
    ) -> EncryptedWorkspaceRecord? {
        values[workspaceID]?[id]
    }

    func replace(_ record: EncryptedWorkspaceRecord) {
        values[record.workspaceID, default: [:]][record.id] = record
    }

    func saveCount(for workspaceID: WorkspaceID) -> Int {
        saves[workspaceID, default: 0]
    }

    func anchorSeenAtFirstSave() -> StoredAuditHeadAnchor? {
        firstSaveAnchor
    }

    func failNextSave() {
        shouldFailNextSave = true
    }
}

private enum AuditInjectedFailure: Error {
    case save
}

private actor AuditMemoryMasterKeyVault: WorkspaceMasterKeyProviding {
    private var keys: [WorkspaceID: SymmetricKey] = [:]
    private(set) var creationCount = 0

    func masterKey(for workspaceID: WorkspaceID, createIfMissing: Bool) -> SymmetricKey? {
        if let key = keys[workspaceID] { return key }
        guard createIfMissing else { return nil }
        creationCount += 1
        let key = SymmetricKey(size: .bits256)
        keys[workspaceID] = key
        return key
    }

    func deleteMasterKey(for workspaceID: WorkspaceID) {
        keys[workspaceID] = nil
    }
}

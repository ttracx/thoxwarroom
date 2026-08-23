import CryptoKit
import Foundation
import Security
import XCTest
@testable import WarRoomAppleInfrastructure
import WarRoomCore

final class EncryptedWorkspaceAuditPolicyStoreTests: XCTestCase {
    func testRoundTripPersistsOnlyCiphertextAndEnforcesCAS() async throws {
        let fixture = try makeFixture()
        let workspaceID = workspace(1)
        let policy = try makePolicy(workspaceID: workspaceID, revision: 1)

        try await fixture.store.save(policy, replacingRevision: nil)

        let loaded = try await fixture.store.policy(for: workspaceID)
        XCTAssertEqual(loaded, policy)
        let storedRecord = await fixture.dataStore.storedRecord(for: workspaceID)
        let record = try XCTUnwrap(storedRecord)
        XCTAssertFalse(String(decoding: record.ciphertext, as: UTF8.self).contains("365"))
        XCTAssertFalse(String(decoding: record.ciphertext, as: UTF8.self).contains("retention"))
        await assertStoreError(.conflictingRevision) {
            try await fixture.store.save(policy, replacingRevision: nil)
        }
    }

    func testAbsentRecordIsNotConfiguredAndDoesNotProvisionKey() async throws {
        let fixture = try makeFixture()

        let loaded = try await fixture.store.policy(for: workspace(1))
        let createCallCount = await fixture.keys.createCallCount
        XCTAssertNil(loaded)
        XCTAssertEqual(createCallCount, 0)
    }

    func testOlderAuthenticatedRecordIsRejectedAsRollback() async throws {
        let fixture = try makeFixture()
        let workspaceID = workspace(1)
        let first = try makePolicy(workspaceID: workspaceID, revision: 1)
        try await fixture.store.save(first, replacingRevision: nil)
        let storedOldRecord = await fixture.dataStore.storedRecord(for: workspaceID)
        let oldRecord = try XCTUnwrap(storedOldRecord)
        let second = try makePolicy(
            workspaceID: workspaceID,
            revision: 2,
            confirmedAt: 200
        )
        try await fixture.store.save(second, replacingRevision: 1)

        await fixture.dataStore.inject(oldRecord, forLookupWorkspace: workspaceID)

        await assertStoreError(.rollbackDetected) {
            _ = try await fixture.store.policy(for: workspaceID)
        }
    }

    func testCiphertextDeletionBehindAnchorIsRejected() async throws {
        let fixture = try makeFixture()
        let workspaceID = workspace(1)
        try await fixture.store.save(
            makePolicy(workspaceID: workspaceID, revision: 1),
            replacingRevision: nil
        )

        await fixture.dataStore.removeRecord(for: workspaceID)

        await assertStoreError(.rollbackDetected) {
            _ = try await fixture.store.policy(for: workspaceID)
        }
    }

    func testMissingAnchorAndCorruptCiphertextFailClosed() async throws {
        let fixture = try makeFixture()
        let workspaceID = workspace(1)
        try await fixture.store.save(
            makePolicy(workspaceID: workspaceID, revision: 1),
            replacingRevision: nil
        )
        let storedOriginal = await fixture.dataStore.storedRecord(for: workspaceID)
        let original = try XCTUnwrap(storedOriginal)

        await fixture.anchors.removeAnchor(for: workspaceID)
        await assertStoreError(.rollbackDetected) {
            _ = try await fixture.store.policy(for: workspaceID)
        }

        await fixture.anchors.set(
            try .validated(
                revision: 1,
                policyDigest: Data(repeating: 7, count: 32)
            ),
            for: workspaceID
        )
        var ciphertext = original.ciphertext
        let firstIndex = ciphertext.startIndex
        ciphertext[firstIndex] ^= 0x01
        let corrupt = try EncryptedWorkspaceRecord(
            id: original.id,
            workspaceID: original.workspaceID,
            collection: original.collection,
            keyReference: original.keyReference,
            nonce: original.nonce,
            ciphertext: ciphertext,
            authenticationTag: original.authenticationTag,
            createdAt: original.createdAt,
            updatedAt: original.updatedAt
        )
        await fixture.dataStore.inject(corrupt, forLookupWorkspace: workspaceID)
        await assertStoreError(.corruptRecord) {
            _ = try await fixture.store.policy(for: workspaceID)
        }
    }

    func testCrossWorkspaceRecordFailsBeforeDecryption() async throws {
        let fixture = try makeFixture()
        let source = workspace(1)
        let destination = workspace(2)
        try await fixture.store.save(
            makePolicy(workspaceID: source, revision: 1),
            replacingRevision: nil
        )
        let storedForeign = await fixture.dataStore.storedRecord(for: source)
        let foreign = try XCTUnwrap(storedForeign)
        await fixture.dataStore.inject(foreign, forLookupWorkspace: destination)
        await fixture.anchors.set(.empty, for: destination)

        await assertStoreError(.crossWorkspaceRecord) {
            _ = try await fixture.store.policy(for: destination)
        }
    }

    func testRecordAheadOfAnchorRecoversAfterInjectedKeychainWriteFailure() async throws {
        let fixture = try makeFixture()
        let workspaceID = workspace(1)
        await fixture.anchors.failNextStore()

        await assertStoreError(.anchorUnavailable) {
            try await fixture.store.save(
                self.makePolicy(workspaceID: workspaceID, revision: 1),
                replacingRevision: nil
            )
        }

        let recovered = try await fixture.store.policy(for: workspaceID)
        let recoveredAnchor = await fixture.anchors.storedAnchor(for: workspaceID)
        XCTAssertEqual(recovered?.revision, 1)
        XCTAssertEqual(recoveredAnchor?.revision, 1)
    }

    func testAnchorAndMasterKeyFailuresAreRedactedAndFailClosed() async throws {
        let fixture = try makeFixture()
        let workspaceID = workspace(1)
        try await fixture.store.save(
            makePolicy(workspaceID: workspaceID, revision: 1),
            replacingRevision: nil
        )

        await fixture.anchors.failReads()
        await assertStoreError(.anchorUnavailable) {
            _ = try await fixture.store.policy(for: workspaceID)
        }
        await fixture.anchors.allowReads()

        let failingCodec = EncryptedWorkspaceRecordCodec(
            keyVault: FailingPolicyKeyVault()
        )
        let keyFailingStore = EncryptedWorkspaceAuditPolicyStore(
            dataStore: fixture.dataStore,
            codec: failingCodec,
            anchorVault: fixture.anchors
        )
        await assertStoreError(.keyUnavailable) {
            _ = try await keyFailingStore.policy(for: workspaceID)
        }
        XCTAssertEqual(
            String(reflecting: EncryptedWorkspaceAuditPolicyStoreError.keyUnavailable),
            "EncryptedWorkspaceAuditPolicyStoreError(<redacted>)"
        )
    }

    func testKeychainAnchorUsesWorkspaceScopedDeviceOnlyNonsynchronizingItem() async throws {
        let client = PolicyAnchorKeychainClient()
        let workspaceID = workspace(1)
        let vault = KeychainWorkspaceAuditPolicyAnchorVault(
            service: "test.audit-policy",
            keychain: client
        )

        _ = try await vault.initializeEmptyAnchor(for: workspaceID)

        let attributes = try XCTUnwrap(client.addedAttributes)
        XCTAssertEqual(attributes[kSecAttrService as String] as? String, "test.audit-policy")
        XCTAssertEqual(
            attributes[kSecAttrAccount as String] as? String,
            "workspace:\(workspaceID.rawValue.uuidString.lowercased()):audit-policy:v1"
        )
        XCTAssertEqual(attributes[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(
            attributes[kSecAttrAccessible as String] as! CFString,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        )
    }

    func testLockedKeychainAnchorMapsWithoutLeakingDetails() async {
        let vault = KeychainWorkspaceAuditPolicyAnchorVault(
            service: "test.audit-policy",
            keychain: PolicyAnchorKeychainClient(copyStatus: errSecInteractionNotAllowed)
        )
        do {
            _ = try await vault.anchor(for: workspace(1))
            XCTFail("Expected locked Keychain")
        } catch {
            XCTAssertEqual(
                error as? WorkspaceAuditPolicyAnchorVaultError,
                .interactionNotAllowed
            )
            XCTAssertEqual(
                String(reflecting: error),
                "WorkspaceAuditPolicyAnchorVaultError(<redacted>)"
            )
        }
    }

    func testCorruptKeychainAnchorFailsClosed() async {
        let vault = KeychainWorkspaceAuditPolicyAnchorVault(
            service: "test.audit-policy",
            keychain: PolicyAnchorKeychainClient(
                copyStatus: errSecSuccess,
                copyData: Data("not-an-anchor".utf8)
            )
        )
        do {
            _ = try await vault.anchor(for: workspace(1))
            XCTFail("Expected corrupt anchor")
        } catch {
            XCTAssertEqual(
                error as? WorkspaceAuditPolicyAnchorVaultError,
                .invalidStoredAnchor
            )
        }
    }

    private func makeFixture() throws -> PolicyFixture {
        let dataStore = PolicyMemoryDataStore()
        let keys = PolicyMemoryKeyVault()
        let anchors = PolicyMemoryAnchorVault()
        return PolicyFixture(
            store: EncryptedWorkspaceAuditPolicyStore(
                dataStore: dataStore,
                codec: EncryptedWorkspaceRecordCodec(keyVault: keys),
                anchorVault: anchors
            ),
            dataStore: dataStore,
            keys: keys,
            anchors: anchors
        )
    }

    private func makePolicy(
        workspaceID: WorkspaceID,
        revision: UInt64,
        confirmedAt: TimeInterval = 100
    ) throws -> ConfirmedWorkspaceAuditPolicy {
        try ConfirmedWorkspaceAuditPolicy(
            workspaceID: workspaceID,
            revision: revision,
            retention: .finite(AuditRetentionDays(rawValue: 365)),
            confirmedAt: Date(timeIntervalSince1970: confirmedAt)
        )
    }

    private func workspace(_ value: UInt8) -> WorkspaceID {
        let suffix = String(format: "%012x", value)
        return WorkspaceID(
            rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-\(suffix)")!
        )
    }

    private func assertStoreError<T>(
        _ expected: EncryptedWorkspaceAuditPolicyStoreError,
        operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected store failure")
        } catch {
            XCTAssertEqual(error as? EncryptedWorkspaceAuditPolicyStoreError, expected)
        }
    }
}

private struct PolicyFixture {
    let store: EncryptedWorkspaceAuditPolicyStore
    let dataStore: PolicyMemoryDataStore
    let keys: PolicyMemoryKeyVault
    let anchors: PolicyMemoryAnchorVault
}

private actor PolicyMemoryDataStore: EncryptedWorkspaceDataStore {
    private var recordsByLookupWorkspace: [WorkspaceID: EncryptedWorkspaceRecord] = [:]

    func record(
        id: EncryptedWorkspaceRecordID,
        in workspaceID: WorkspaceID
    ) -> EncryptedWorkspaceRecord? {
        guard let record = recordsByLookupWorkspace[workspaceID], record.id == id else {
            return nil
        }
        return record
    }

    func records(
        in workspaceID: WorkspaceID,
        collection: WorkspaceDataCollection,
        limit: WorkspaceDataPageLimit
    ) -> [EncryptedWorkspaceRecord] {
        guard let record = recordsByLookupWorkspace[workspaceID],
              record.collection == collection else { return [] }
        return [record]
    }

    func save(_ record: EncryptedWorkspaceRecord) {
        recordsByLookupWorkspace[record.workspaceID] = record
    }

    func deleteRecord(id: EncryptedWorkspaceRecordID, in workspaceID: WorkspaceID) {
        if recordsByLookupWorkspace[workspaceID]?.id == id {
            recordsByLookupWorkspace.removeValue(forKey: workspaceID)
        }
    }

    func storedRecord(for workspaceID: WorkspaceID) -> EncryptedWorkspaceRecord? {
        recordsByLookupWorkspace[workspaceID]
    }

    func inject(_ record: EncryptedWorkspaceRecord, forLookupWorkspace workspaceID: WorkspaceID) {
        recordsByLookupWorkspace[workspaceID] = record
    }

    func removeRecord(for workspaceID: WorkspaceID) {
        recordsByLookupWorkspace.removeValue(forKey: workspaceID)
    }
}

private actor PolicyMemoryKeyVault: WorkspaceMasterKeyProviding {
    private var keys: [WorkspaceID: SymmetricKey] = [:]
    private(set) var createCallCount = 0

    func masterKey(for workspaceID: WorkspaceID, createIfMissing: Bool) -> SymmetricKey? {
        if let key = keys[workspaceID] { return key }
        guard createIfMissing else { return nil }
        createCallCount += 1
        let key = SymmetricKey(size: .bits256)
        keys[workspaceID] = key
        return key
    }

    func deleteMasterKey(for workspaceID: WorkspaceID) {
        keys.removeValue(forKey: workspaceID)
    }
}

private actor FailingPolicyKeyVault: WorkspaceMasterKeyProviding {
    func masterKey(for workspaceID: WorkspaceID, createIfMissing: Bool) throws
        -> SymmetricKey? {
        throw WorkspaceMasterKeyVaultError.interactionNotAllowed
    }

    func deleteMasterKey(for workspaceID: WorkspaceID) throws {
        throw WorkspaceMasterKeyVaultError.interactionNotAllowed
    }
}

private actor PolicyMemoryAnchorVault: WorkspaceAuditPolicyAnchorProviding {
    private var anchors: [WorkspaceID: StoredWorkspaceAuditPolicyAnchor] = [:]
    private var shouldFailNextStore = false
    private var shouldFailReads = false

    func anchor(for workspaceID: WorkspaceID) throws -> StoredWorkspaceAuditPolicyAnchor? {
        if shouldFailReads {
            throw WorkspaceAuditPolicyAnchorVaultError.interactionNotAllowed
        }
        return anchors[workspaceID]
    }

    func initializeEmptyAnchor(for workspaceID: WorkspaceID) throws
        -> StoredWorkspaceAuditPolicyAnchor {
        if shouldFailReads {
            throw WorkspaceAuditPolicyAnchorVaultError.interactionNotAllowed
        }
        if let existing = anchors[workspaceID] { return existing }
        anchors[workspaceID] = .empty
        return .empty
    }

    func store(
        _ anchor: StoredWorkspaceAuditPolicyAnchor,
        for workspaceID: WorkspaceID
    ) throws {
        if shouldFailNextStore {
            shouldFailNextStore = false
            throw WorkspaceAuditPolicyAnchorVaultError.interactionNotAllowed
        }
        guard anchors[workspaceID] != nil else {
            throw WorkspaceAuditPolicyAnchorVaultError.missingAnchor
        }
        anchors[workspaceID] = anchor
    }

    func failNextStore() { shouldFailNextStore = true }
    func failReads() { shouldFailReads = true }
    func allowReads() { shouldFailReads = false }
    func removeAnchor(for workspaceID: WorkspaceID) { anchors.removeValue(forKey: workspaceID) }
    func set(_ anchor: StoredWorkspaceAuditPolicyAnchor, for workspaceID: WorkspaceID) {
        anchors[workspaceID] = anchor
    }
    func storedAnchor(for workspaceID: WorkspaceID) -> StoredWorkspaceAuditPolicyAnchor? {
        anchors[workspaceID]
    }
}

private final class PolicyAnchorKeychainClient: KeychainItemClient, @unchecked Sendable {
    private let lock = NSLock()
    private let copyStatus: OSStatus
    private let copyData: Data?
    private(set) var addedAttributes: [String: Any]?

    init(
        copyStatus: OSStatus = errSecItemNotFound,
        copyData: Data? = nil
    ) {
        self.copyStatus = copyStatus
        self.copyData = copyData
    }

    func copyMatching(_ query: [String: Any]) -> KeychainCopyResult {
        KeychainCopyResult(status: copyStatus, data: copyData)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.withLock { addedAttributes = attributes }
        return errSecSuccess
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus { errSecSuccess }
}

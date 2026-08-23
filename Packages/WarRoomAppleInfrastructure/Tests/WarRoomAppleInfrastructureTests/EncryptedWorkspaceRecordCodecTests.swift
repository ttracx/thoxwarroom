import CryptoKit
import Foundation
import XCTest
@testable import WarRoomAppleInfrastructure
import WarRoomCore

final class EncryptedWorkspaceRecordCodecTests: XCTestCase {
    func testRequiresExplicitProvisioningThenRoundTripsWithoutPlaintext() async throws {
        let vault = MemoryMasterKeyVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: vault)
        let workspaceID = fixedWorkspaceID()
        let collection = try WorkspaceDataCollection(validating: "workspace.profile")
        let secret = Data("private endpoint and workspace metadata".utf8)

        do {
            _ = try await codec.seal(secret, workspaceID: workspaceID, collection: collection)
            XCTFail("Expected missing key")
        } catch {
            XCTAssertEqual(error as? EncryptedWorkspaceRecordCodecError, .masterKeyMissing)
        }
        let creationCountBeforeProvisioning = await vault.creationCount
        XCTAssertEqual(creationCountBeforeProvisioning, 0)

        try await codec.provisionMasterKey(for: workspaceID)
        let record = try await codec.seal(secret, workspaceID: workspaceID, collection: collection)
        let encoded = try JSONEncoder().encode(record)

        let opened = try await codec.open(record)
        XCTAssertEqual(opened, secret)
        XCTAssertFalse(encoded.range(of: secret) != nil)
        let creationCountAfterProvisioning = await vault.creationCount
        XCTAssertEqual(creationCountAfterProvisioning, 1)
    }

    func testRepeatedSealUsesDistinctNoncesAndCiphertext() async throws {
        let vault = MemoryMasterKeyVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: vault)
        let workspaceID = fixedWorkspaceID()
        let collection = try WorkspaceDataCollection(validating: "private.documents")
        let recordID = fixedRecordID()
        try await codec.provisionMasterKey(for: workspaceID)

        let first = try await codec.seal(
            Data("same plaintext".utf8),
            workspaceID: workspaceID,
            collection: collection,
            recordID: recordID
        )
        let second = try await codec.seal(
            Data("same plaintext".utf8),
            workspaceID: workspaceID,
            collection: collection,
            recordID: recordID
        )

        XCTAssertNotEqual(first.nonce, second.nonce)
        XCTAssertNotEqual(first.ciphertext, second.ciphertext)
    }

    func testRejectsCiphertextWrongKeyAndCrossWorkspaceContext() async throws {
        let firstVault = MemoryMasterKeyVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: firstVault)
        let workspaceID = fixedWorkspaceID()
        let collection = try WorkspaceDataCollection(validating: "private.documents")
        try await codec.provisionMasterKey(for: workspaceID)
        let record = try await codec.seal(
            Data("protected".utf8),
            workspaceID: workspaceID,
            collection: collection,
            recordID: fixedRecordID()
        )

        var tamperedCiphertext = record.ciphertext
        tamperedCiphertext[tamperedCiphertext.startIndex] ^= 0xff
        let tampered = try copy(record, ciphertext: tamperedCiphertext)
        await assertAuthenticationFailure { try await codec.open(tampered) }

        let wrongVault = MemoryMasterKeyVault()
        await wrongVault.set(SymmetricKey(size: .bits256), for: workspaceID)
        let wrongCodec = EncryptedWorkspaceRecordCodec(keyVault: wrongVault)
        await assertAuthenticationFailure { try await wrongCodec.open(record) }

        let otherWorkspace = WorkspaceID(rawValue: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!)
        let firstKey = await firstVault.key(for: workspaceID)
        await firstVault.set(try XCTUnwrap(firstKey), for: otherWorkspace)
        let moved = try copy(record, workspaceID: otherWorkspace)
        await assertAuthenticationFailure { try await codec.open(moved) }
    }

    func testAuthenticatesCollectionRecordIdentityAndTimestamps() async throws {
        let vault = MemoryMasterKeyVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: vault)
        let workspaceID = fixedWorkspaceID()
        let collection = try WorkspaceDataCollection(validating: "private.documents")
        try await codec.provisionMasterKey(for: workspaceID)
        let record = try await codec.seal(
            Data("protected".utf8),
            workspaceID: workspaceID,
            collection: collection,
            recordID: fixedRecordID(),
            createdAt: Date(timeIntervalSince1970: 100.1234),
            updatedAt: Date(timeIntervalSince1970: 101.5678)
        )

        let movedCollection = try copy(
            record,
            collection: WorkspaceDataCollection(validating: "model.cache")
        )
        await assertAuthenticationFailure { try await codec.open(movedCollection) }
        let movedRecord = try copy(
            record,
            recordID: EncryptedWorkspaceRecordID(rawValue: UUID())
        )
        await assertAuthenticationFailure { try await codec.open(movedRecord) }
        let changedTimestamp = try copy(
            record,
            updatedAt: record.updatedAt.addingTimeInterval(0.001)
        )
        await assertAuthenticationFailure { try await codec.open(changedTimestamp) }
        XCTAssertEqual(record.createdAt.timeIntervalSince1970, 100.123, accuracy: 0.000_001)
        XCTAssertEqual(record.updatedAt.timeIntervalSince1970, 101.568, accuracy: 0.000_001)
    }

    func testRejectsInvalidDatesAndRedactsFailures() async throws {
        let vault = MemoryMasterKeyVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: vault)
        let workspaceID = fixedWorkspaceID()
        let collection = try WorkspaceDataCollection(validating: "workspace.profile")
        try await codec.provisionMasterKey(for: workspaceID)

        for timestamp in [Double.nan, Double.infinity, -Double.infinity] {
            do {
                _ = try await codec.seal(
                    Data([1]),
                    workspaceID: workspaceID,
                    collection: collection,
                    createdAt: Date(timeIntervalSince1970: timestamp),
                    updatedAt: Date(timeIntervalSince1970: timestamp)
                )
                XCTFail("Expected invalid timestamp")
            } catch {
                XCTAssertEqual(error as? EncryptedWorkspaceRecordCodecError, .invalidTimestamp)
                XCTAssertEqual(String(describing: error), "Encrypted workspace data is unavailable.")
            }
        }
    }

    func testMasterKeyDeletionIsIdempotentAndMakesCiphertextUnreadable() async throws {
        let vault = MemoryMasterKeyVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: vault)
        let workspaceID = fixedWorkspaceID()
        let collection = try WorkspaceDataCollection(validating: "private.documents")
        try await codec.provisionMasterKey(for: workspaceID)
        let record = try await codec.seal(
            Data("protected".utf8),
            workspaceID: workspaceID,
            collection: collection
        )

        try await codec.deleteMasterKey(for: workspaceID)
        try await codec.deleteMasterKey(for: workspaceID)

        do {
            _ = try await codec.open(record)
            XCTFail("Expected cryptographic erasure")
        } catch {
            XCTAssertEqual(error as? EncryptedWorkspaceRecordCodecError, .masterKeyMissing)
        }
    }

    private func assertAuthenticationFailure(
        _ operation: () async throws -> Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected authentication failure", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? EncryptedWorkspaceRecordCodecError,
                .authenticationFailed,
                file: file,
                line: line
            )
        }
    }

    private func copy(
        _ record: EncryptedWorkspaceRecord,
        workspaceID: WorkspaceID? = nil,
        collection: WorkspaceDataCollection? = nil,
        recordID: EncryptedWorkspaceRecordID? = nil,
        ciphertext: Data? = nil,
        updatedAt: Date? = nil
    ) throws -> EncryptedWorkspaceRecord {
        try EncryptedWorkspaceRecord(
            id: recordID ?? record.id,
            workspaceID: workspaceID ?? record.workspaceID,
            collection: collection ?? record.collection,
            algorithm: record.algorithm,
            keyReference: record.keyReference,
            nonce: record.nonce,
            ciphertext: ciphertext ?? record.ciphertext,
            authenticationTag: record.authenticationTag,
            createdAt: record.createdAt,
            updatedAt: updatedAt ?? record.updatedAt
        )
    }

    private func fixedWorkspaceID() -> WorkspaceID {
        WorkspaceID(rawValue: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
    }

    private func fixedRecordID() -> EncryptedWorkspaceRecordID {
        EncryptedWorkspaceRecordID(rawValue: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!)
    }
}

private actor MemoryMasterKeyVault: WorkspaceMasterKeyProviding {
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

    func set(_ key: SymmetricKey, for workspaceID: WorkspaceID) {
        keys[workspaceID] = key
    }

    func key(for workspaceID: WorkspaceID) -> SymmetricKey? {
        keys[workspaceID]
    }
}

import Foundation
import XCTest
@testable import WarRoomCore

final class EncryptedWorkspaceDataTests: XCTestCase {
    func testEncryptedRecordRoundTripsWithoutExposingProtectedValuesInDescriptions() throws {
        let keyReferenceValue = "workspace-key-private-reference"
        let ciphertext = Data("synthetic-ciphertext".utf8)
        let record = try makeRecord(
            keyReference: EncryptionKeyReference(keyReferenceValue),
            ciphertext: ciphertext
        )

        let encoded = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(EncryptedWorkspaceRecord.self, from: encoded), record)
        XCTAssertEqual(record.description, "EncryptedWorkspaceRecord(<redacted>)")
        XCTAssertFalse(String(describing: record).contains(keyReferenceValue))
        XCTAssertFalse(String(describing: record).contains(ciphertext.base64EncodedString()))
        XCTAssertEqual(record.keyReference.description, "<redacted-key-reference>")
    }

    func testRejectsMalformedAuthenticatedEncryptionEnvelope() throws {
        let workspaceID = WorkspaceID.make()
        let collection = try WorkspaceDataCollection(validating: "private.documents")
        let keyReference = try EncryptionKeyReference("workspace-key")
        let createdAt = Date(timeIntervalSince1970: 100)

        XCTAssertThrowsError(try EncryptedWorkspaceRecord(
            workspaceID: workspaceID,
            collection: collection,
            keyReference: keyReference,
            nonce: Data(repeating: 0, count: 11),
            ciphertext: Data([1]),
            authenticationTag: Data(repeating: 0, count: 16)
        )) { error in
            XCTAssertEqual(error as? EncryptedWorkspaceDataError, .invalidNonceLength(actual: 11))
        }
        XCTAssertThrowsError(try EncryptedWorkspaceRecord(
            workspaceID: workspaceID,
            collection: collection,
            keyReference: keyReference,
            nonce: Data(repeating: 0, count: 12),
            ciphertext: Data(),
            authenticationTag: Data(repeating: 0, count: 16)
        )) { error in
            XCTAssertEqual(error as? EncryptedWorkspaceDataError, .emptyCiphertext)
        }
        XCTAssertThrowsError(try EncryptedWorkspaceRecord(
            workspaceID: workspaceID,
            collection: collection,
            keyReference: keyReference,
            nonce: Data(repeating: 0, count: 12),
            ciphertext: Data([1]),
            authenticationTag: Data(repeating: 0, count: 15)
        )) { error in
            XCTAssertEqual(
                error as? EncryptedWorkspaceDataError,
                .invalidAuthenticationTagLength(actual: 15)
            )
        }
        XCTAssertThrowsError(try EncryptedWorkspaceRecord(
            workspaceID: workspaceID,
            collection: collection,
            keyReference: keyReference,
            nonce: Data(repeating: 0, count: 12),
            ciphertext: Data([1]),
            authenticationTag: Data(repeating: 0, count: 16),
            createdAt: createdAt,
            updatedAt: createdAt.addingTimeInterval(-1)
        )) { error in
            XCTAssertEqual(error as? EncryptedWorkspaceDataError, .updatedBeforeCreation)
        }
    }

    func testRejectsOversizedCiphertextAndInvalidRoutingValues() throws {
        let oversizedCount = EncryptedWorkspaceRecord.maximumCiphertextBytes + 1
        XCTAssertThrowsError(try makeRecord(ciphertext: Data(repeating: 7, count: oversizedCount))) {
            error in
            XCTAssertEqual(
                error as? EncryptedWorkspaceDataError,
                .ciphertextTooLarge(
                    limit: EncryptedWorkspaceRecord.maximumCiphertextBytes,
                    actual: oversizedCount
                )
            )
        }

        for collection in ["", "UPPERCASE", "private documents", String(repeating: "a", count: 65)] {
            XCTAssertNil(WorkspaceDataCollection(rawValue: collection))
            XCTAssertThrowsError(try WorkspaceDataCollection(validating: collection))
        }
        for reference in ["", "contains space", String(repeating: "k", count: 129)] {
            XCTAssertThrowsError(try EncryptionKeyReference(reference))
        }
        for limit in [0, WorkspaceDataPageLimit.maximum + 1] {
            XCTAssertThrowsError(try WorkspaceDataPageLimit(rawValue: limit)) { error in
                XCTAssertEqual(error as? WorkspaceDataPageLimitError, .outOfRange(limit))
            }
        }
    }

    func testDecodedEnvelopeRevalidatesCiphertextBounds() throws {
        let record = try makeRecord()
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any]
        )
        object["nonce"] = Data(repeating: 0, count: 4).base64EncodedString()
        let tampered = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try JSONDecoder().decode(EncryptedWorkspaceRecord.self, from: tampered)) {
            XCTAssertTrue($0 is DecodingError)
        }
    }

    func testOfflineStoreSeamEnforcesWorkspaceAndCollectionIsolation() async throws {
        let firstWorkspace = WorkspaceID.make()
        let secondWorkspace = WorkspaceID.make()
        let first = try makeRecord(workspaceID: firstWorkspace, collection: "private.documents")
        let second = try makeRecord(workspaceID: secondWorkspace, collection: "private.documents")
        let otherCollection = try makeRecord(workspaceID: firstWorkspace, collection: "model.cache")
        let store: any EncryptedWorkspaceDataStore = IsolatedEncryptedRecordStore()
        try await store.save(first)
        try await store.save(second)
        try await store.save(otherCollection)

        let firstWorkspaceRecord = try await store.record(id: first.id, in: firstWorkspace)
        let crossWorkspaceRecord = try await store.record(id: first.id, in: secondWorkspace)
        let collectionRecords = try await store.records(
            in: firstWorkspace,
            collection: try WorkspaceDataCollection(validating: "private.documents"),
            limit: .standard
        )
        XCTAssertEqual(firstWorkspaceRecord, first)
        XCTAssertNil(crossWorkspaceRecord)
        XCTAssertEqual(collectionRecords, [first])

        try await store.deleteRecord(id: first.id, in: secondWorkspace)
        let recordAfterCrossWorkspaceDelete = try await store.record(
            id: first.id,
            in: firstWorkspace
        )
        XCTAssertEqual(recordAfterCrossWorkspaceDelete, first)
        try await store.deleteRecord(id: first.id, in: firstWorkspace)
        let deletedRecord = try await store.record(id: first.id, in: firstWorkspace)
        XCTAssertNil(deletedRecord)
    }

    private func makeRecord(
        workspaceID: WorkspaceID = .make(),
        collection: String = "private.documents",
        keyReference: EncryptionKeyReference? = nil,
        ciphertext: Data = Data("ciphertext".utf8)
    ) throws -> EncryptedWorkspaceRecord {
        try EncryptedWorkspaceRecord(
            workspaceID: workspaceID,
            collection: WorkspaceDataCollection(validating: collection),
            keyReference: keyReference ?? EncryptionKeyReference("workspace-key"),
            nonce: Data(repeating: 1, count: EncryptedWorkspaceRecord.nonceBytes),
            ciphertext: ciphertext,
            authenticationTag: Data(
                repeating: 2,
                count: EncryptedWorkspaceRecord.authenticationTagBytes
            ),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 101)
        )
    }
}

private actor IsolatedEncryptedRecordStore: EncryptedWorkspaceDataStore {
    private var values: [WorkspaceID: [EncryptedWorkspaceRecordID: EncryptedWorkspaceRecord]] = [:]

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
        Array(
            (values[workspaceID]?.values ?? [:].values)
                .filter { $0.collection == collection }
                .sorted { $0.updatedAt < $1.updatedAt }
                .prefix(limit.rawValue)
        )
    }

    func save(_ record: EncryptedWorkspaceRecord) {
        values[record.workspaceID, default: [:]][record.id] = record
    }

    func deleteRecord(
        id: EncryptedWorkspaceRecordID,
        in workspaceID: WorkspaceID
    ) {
        values[workspaceID]?[id] = nil
    }
}

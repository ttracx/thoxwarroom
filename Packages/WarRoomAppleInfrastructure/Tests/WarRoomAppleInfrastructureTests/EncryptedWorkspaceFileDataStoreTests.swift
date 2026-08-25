import CryptoKit
import Foundation
import XCTest
@testable import WarRoomAppleInfrastructure
import WarRoomCore

final class EncryptedWorkspaceFileDataStoreTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("warroom-file-store-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot { try? FileManager.default.removeItem(at: temporaryRoot) }
        temporaryRoot = nil
    }

    func testEncryptedPayloadRoundTripsAndPlaintextIsAbsentFromFile() async throws {
        let fileSystem = SystemAtomicWorkspaceFileSystem()
        let store = try EncryptedWorkspaceFileDataStore(rootURL: temporaryRoot, fileSystem: fileSystem)
        let vault = FileTestMasterKeyVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: vault)
        let workspaceID = workspaceID("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let collection = try WorkspaceDataCollection(validating: "private.documents")
        let secret = Data("private-provider-endpoint-and-metadata".utf8)
        try await codec.provisionMasterKey(for: workspaceID)
        let record = try await codec.seal(
            secret,
            workspaceID: workspaceID,
            collection: collection,
            recordID: recordID("CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")
        )

        try await store.save(record)

        let loadedRecord = try await store.record(id: record.id, in: workspaceID)
        let loaded = try XCTUnwrap(loadedRecord)
        let opened = try await codec.open(loaded)
        XCTAssertEqual(opened, secret)
        let raw = try fileSystem.readBoundedFile(
            at: fileURL(for: record),
            maximumBytes: EncryptedWorkspaceFileDataStore.maximumEncodedRecordBytes
        )
        XCTAssertNil(try XCTUnwrap(raw).range(of: secret))
        let workspaceIDs = try await store.workspaceIDs()
        XCTAssertEqual(workspaceIDs, [workspaceID])
    }

    func testNonceVariancePersistsDistinctAuthenticatedRecords() async throws {
        let store = try EncryptedWorkspaceFileDataStore(
            rootURL: temporaryRoot,
            fileSystem: SystemAtomicWorkspaceFileSystem()
        )
        let vault = FileTestMasterKeyVault()
        let codec = EncryptedWorkspaceRecordCodec(keyVault: vault)
        let workspaceID = workspaceID("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let collection = try WorkspaceDataCollection(validating: "private.documents")
        try await codec.provisionMasterKey(for: workspaceID)
        let first = try await codec.seal(
            Data("same".utf8),
            workspaceID: workspaceID,
            collection: collection
        )
        let second = try await codec.seal(
            Data("same".utf8),
            workspaceID: workspaceID,
            collection: collection
        )

        try await store.save(first)
        try await store.save(second)
        let records = try await store.records(in: workspaceID, collection: collection, limit: .standard)

        XCTAssertEqual(records.count, 2)
        XCTAssertNotEqual(records[0].nonce, records[1].nonce)
    }

    func testMissingWorkspaceRecordLookupReturnsNil() async throws {
        let store = try EncryptedWorkspaceFileDataStore(
            rootURL: temporaryRoot,
            fileSystem: SystemAtomicWorkspaceFileSystem()
        )
        let workspaceID = workspaceID("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let recordID = recordID("CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")

        let record = try await store.record(id: recordID, in: workspaceID)

        XCTAssertNil(record)
    }

    func testInjectedAtomicWriteFailurePreservesPreviousRecord() async throws {
        let fileSystem = FailAfterFirstWriteFileSystem()
        let store = try EncryptedWorkspaceFileDataStore(rootURL: temporaryRoot, fileSystem: fileSystem)
        let workspaceID = workspaceID("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let collection = try WorkspaceDataCollection(validating: "private.documents")
        let id = recordID("CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")
        let first = try makeRecord(
            id: id,
            workspaceID: workspaceID,
            collection: collection,
            ciphertext: Data("first-ciphertext".utf8)
        )
        let replacement = try makeRecord(
            id: id,
            workspaceID: workspaceID,
            collection: collection,
            ciphertext: Data("replacement-ciphertext".utf8),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        try await store.save(first)

        do {
            try await store.save(replacement)
            XCTFail("Expected injected write failure")
        } catch {
            XCTAssertEqual(error as? EncryptedWorkspaceFileStoreError, .inputOutputFailure)
        }

        let preserved = try await store.record(id: id, in: workspaceID)
        XCTAssertEqual(preserved, first)
    }

    func testCorruptionAndOversizedFilesFailClosedWithRedactedErrors() async throws {
        let fileSystem = SystemAtomicWorkspaceFileSystem()
        let store = try EncryptedWorkspaceFileDataStore(rootURL: temporaryRoot, fileSystem: fileSystem)
        let record = try makeRecord()
        try await store.save(record)
        try Data("corrupt-secret-evidence".utf8).write(to: fileURL(for: record), options: .atomic)

        do {
            _ = try await store.record(id: record.id, in: record.workspaceID)
            XCTFail("Expected corrupt record")
        } catch {
            XCTAssertEqual(error as? EncryptedWorkspaceFileStoreError, .corruptRecord)
            XCTAssertEqual(String(describing: error), "Encrypted workspace storage is unavailable.")
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL(for: record).path))
        }

        let oversized = Data(
            repeating: 7,
            count: EncryptedWorkspaceFileDataStore.maximumEncodedRecordBytes + 1
        )
        try oversized.write(to: fileURL(for: record), options: .atomic)
        do {
            _ = try await store.record(id: record.id, in: record.workspaceID)
            XCTFail("Expected size rejection")
        } catch {
            guard case .encodedRecordTooLarge(let limit, let actual) =
                error as? EncryptedWorkspaceFileStoreError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(limit, EncryptedWorkspaceFileDataStore.maximumEncodedRecordBytes)
            XCTAssertEqual(actual, limit + 1)
        }
    }

    func testWorkspaceDeletionAndCrossWorkspaceRecordDeletionAreIsolated() async throws {
        let store = try EncryptedWorkspaceFileDataStore(
            rootURL: temporaryRoot,
            fileSystem: SystemAtomicWorkspaceFileSystem()
        )
        let firstWorkspace = workspaceID("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let secondWorkspace = workspaceID("BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
        let sharedID = recordID("CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")
        let collection = try WorkspaceDataCollection(validating: "private.documents")
        let first = try makeRecord(id: sharedID, workspaceID: firstWorkspace, collection: collection)
        let second = try makeRecord(id: sharedID, workspaceID: secondWorkspace, collection: collection)
        try await store.save(first)
        try await store.save(second)

        try await store.deleteRecord(id: sharedID, in: firstWorkspace)
        let deletedFirst = try await store.record(id: sharedID, in: firstWorkspace)
        let preservedSecond = try await store.record(id: sharedID, in: secondWorkspace)
        XCTAssertNil(deletedFirst)
        XCTAssertEqual(preservedSecond, second)

        try await store.deleteWorkspace(id: firstWorkspace)
        try await store.deleteWorkspace(id: firstWorkspace)
        let secondAfterWorkspaceDeletion = try await store.record(
            id: sharedID,
            in: secondWorkspace
        )
        XCTAssertEqual(secondAfterWorkspaceDeletion, second)
    }

    func testCollectionSymlinkIsRejectedWithoutFollowingIt() async throws {
        let fileSystem = SystemAtomicWorkspaceFileSystem()
        let store = try EncryptedWorkspaceFileDataStore(rootURL: temporaryRoot, fileSystem: fileSystem)
        let workspaceID = workspaceID("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let workspaceURL = temporaryRoot.appendingPathComponent(
            workspaceID.rawValue.uuidString.lowercased(),
            isDirectory: true
        )
        try fileSystem.ensurePrivateDirectory(at: workspaceURL)
        let external = FileManager.default.temporaryDirectory
            .appendingPathComponent("warroom-symlink-target-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: external) }
        try FileManager.default.createSymbolicLink(
            at: workspaceURL.appendingPathComponent("private.documents"),
            withDestinationURL: external
        )

        do {
            _ = try await store.records(
                in: workspaceID,
                collection: WorkspaceDataCollection(validating: "private.documents"),
                limit: .standard
            )
            XCTFail("Expected symlink rejection")
        } catch {
            XCTAssertEqual(
                error as? EncryptedWorkspaceFileStoreError,
                .symbolicLinkEncountered
            )
        }
    }

    private func makeRecord(
        id: EncryptedWorkspaceRecordID = EncryptedWorkspaceRecordID(rawValue: UUID()),
        workspaceID: WorkspaceID? = nil,
        collection: WorkspaceDataCollection? = nil,
        ciphertext: Data = Data("synthetic-ciphertext".utf8),
        updatedAt: Date = Date(timeIntervalSince1970: 101)
    ) throws -> EncryptedWorkspaceRecord {
        try EncryptedWorkspaceRecord(
            id: id,
            workspaceID: workspaceID ?? self.workspaceID("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"),
            collection: try collection ?? WorkspaceDataCollection(validating: "private.documents"),
            keyReference: EncryptionKeyReference("workspace-master-v1"),
            nonce: Data(repeating: 1, count: EncryptedWorkspaceRecord.nonceBytes),
            ciphertext: ciphertext,
            authenticationTag: Data(repeating: 2, count: EncryptedWorkspaceRecord.authenticationTagBytes),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: updatedAt
        )
    }

    private func fileURL(for record: EncryptedWorkspaceRecord) -> URL {
        temporaryRoot
            .appendingPathComponent(record.workspaceID.rawValue.uuidString.lowercased())
            .appendingPathComponent(record.collection.rawValue)
            .appendingPathComponent(record.id.rawValue.uuidString.lowercased() + ".thoxenc")
    }

    private func workspaceID(_ value: String) -> WorkspaceID {
        WorkspaceID(rawValue: UUID(uuidString: value)!)
    }

    private func recordID(_ value: String) -> EncryptedWorkspaceRecordID {
        EncryptedWorkspaceRecordID(rawValue: UUID(uuidString: value)!)
    }
}

private actor FileTestMasterKeyVault: WorkspaceMasterKeyProviding {
    private var keys: [WorkspaceID: SymmetricKey] = [:]

    func masterKey(for workspaceID: WorkspaceID, createIfMissing: Bool) -> SymmetricKey? {
        if let key = keys[workspaceID] { return key }
        guard createIfMissing else { return nil }
        let key = SymmetricKey(size: .bits256)
        keys[workspaceID] = key
        return key
    }

    func deleteMasterKey(for workspaceID: WorkspaceID) {
        keys[workspaceID] = nil
    }
}

private final class FailAfterFirstWriteFileSystem: AtomicWorkspaceFileSystem,
    @unchecked Sendable {
    private let system = SystemAtomicWorkspaceFileSystem()
    private let lock = NSLock()
    private var writeCount = 0

    func ensurePrivateDirectory(at url: URL) throws { try system.ensurePrivateDirectory(at: url) }
    func directoryEntries(at url: URL) throws -> [URL] { try system.directoryEntries(at: url) }
    func readBoundedFile(at url: URL, maximumBytes: Int) throws -> Data? {
        try system.readBoundedFile(at: url, maximumBytes: maximumBytes)
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        let shouldFail = lock.withLock { () -> Bool in
            writeCount += 1
            return writeCount > 1
        }
        if shouldFail { throw EncryptedWorkspaceFileStoreError.inputOutputFailure }
        try system.writeAtomically(data, to: url)
    }

    func removeFileIfPresent(at url: URL) throws { try system.removeFileIfPresent(at: url) }
    func removeDirectoryIfPresent(at url: URL) throws {
        try system.removeDirectoryIfPresent(at: url)
    }
}

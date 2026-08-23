import Foundation
import Security
import XCTest
@testable import WarRoomAppleInfrastructure
import WarRoomCore

final class KeychainWorkspaceDeletionJournalTests: XCTestCase {
    func testSaveUsesIndependentNonSynchronizingLockedDeviceItem() async throws {
        let client = DeletionJournalKeychainClient(
            copyResult: .init(status: errSecItemNotFound, data: nil),
            updateStatuses: [errSecItemNotFound]
        )
        let journal = KeychainWorkspaceDeletionJournal(
            service: "test.deletion-journal",
            keychain: client
        )
        let entry = WorkspaceDeletionJournalEntry(
            workspaceID: fixedWorkspaceID(),
            stage: .credentialDeletionPending
        )

        try await journal.save(entry)

        let attributes = try XCTUnwrap(client.addedAttributes)
        XCTAssertEqual(attributes[kSecAttrService as String] as? String, "test.deletion-journal")
        XCTAssertEqual(attributes[kSecAttrAccount as String] as? String, "pending:v1")
        XCTAssertEqual(attributes[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(
            attributes[kSecAttrAccessible as String] as! CFString,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        )
        let data = try XCTUnwrap(attributes[kSecValueData as String] as? Data)
        XCTAssertEqual(try JSONDecoder().decode(WorkspaceDeletionJournalEntry.self, from: data), entry)
    }

    func testReadsEntryAndDescriptionsRedactWorkspaceIdentifier() async throws {
        let entry = WorkspaceDeletionJournalEntry(
            workspaceID: fixedWorkspaceID(),
            stage: .encryptedWorkspaceDeletionPending
        )
        let data = try JSONEncoder().encode(entry)
        let client = DeletionJournalKeychainClient(
            copyResult: .init(status: errSecSuccess, data: data)
        )
        let journal = KeychainWorkspaceDeletionJournal(
            service: "test.deletion-journal",
            keychain: client
        )

        let loaded = try await journal.pendingEntry()

        XCTAssertEqual(loaded, entry)
        XCTAssertFalse(String(describing: entry).contains(fixedWorkspaceID().rawValue.uuidString))
        XCTAssertTrue(String(describing: entry).contains("<redacted>"))
    }

    func testCorruptEntryAndLockedKeychainProduceTypedNonSensitiveErrors() async {
        let corrupt = KeychainWorkspaceDeletionJournal(
            service: "test.deletion-journal",
            keychain: DeletionJournalKeychainClient(
                copyResult: .init(status: errSecSuccess, data: Data("not-json".utf8))
            )
        )
        do {
            _ = try await corrupt.pendingEntry()
            XCTFail("Expected corrupt journal rejection")
        } catch {
            XCTAssertEqual(
                error as? KeychainWorkspaceDeletionJournalError,
                .invalidStoredEntry
            )
        }

        let locked = KeychainWorkspaceDeletionJournal(
            service: "test.deletion-journal",
            keychain: DeletionJournalKeychainClient(
                copyResult: .init(status: errSecInteractionNotAllowed, data: nil)
            )
        )
        do {
            _ = try await locked.pendingEntry()
            XCTFail("Expected locked Keychain rejection")
        } catch {
            XCTAssertEqual(
                error as? KeychainWorkspaceDeletionJournalError,
                .interactionNotAllowed
            )
        }
    }

    func testClearIsIdempotentAndScopedToJournalAccount() async throws {
        let client = DeletionJournalKeychainClient(
            copyResult: .init(status: errSecItemNotFound, data: nil),
            deleteStatus: errSecItemNotFound
        )
        let journal = KeychainWorkspaceDeletionJournal(
            service: "test.deletion-journal",
            keychain: client
        )

        try await journal.clear()

        XCTAssertEqual(client.deletedQuery?[kSecAttrService as String] as? String, "test.deletion-journal")
        XCTAssertEqual(client.deletedQuery?[kSecAttrAccount as String] as? String, "pending:v1")
    }

    private func fixedWorkspaceID() -> WorkspaceID {
        WorkspaceID(rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!)
    }
}

private final class DeletionJournalKeychainClient: KeychainItemClient, @unchecked Sendable {
    private let lock = NSLock()
    private let copyResult: KeychainCopyResult
    private var updateStatuses: [OSStatus]
    private let addStatus: OSStatus
    private let deleteStatus: OSStatus

    private(set) var addedAttributes: [String: Any]?
    private(set) var deletedQuery: [String: Any]?

    init(
        copyResult: KeychainCopyResult,
        updateStatuses: [OSStatus] = [],
        addStatus: OSStatus = errSecSuccess,
        deleteStatus: OSStatus = errSecSuccess
    ) {
        self.copyResult = copyResult
        self.updateStatuses = updateStatuses
        self.addStatus = addStatus
        self.deleteStatus = deleteStatus
    }

    func copyMatching(_ query: [String: Any]) -> KeychainCopyResult { copyResult }

    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.withLock { addedAttributes = attributes }
        return addStatus
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            updateStatuses.isEmpty ? errSecSuccess : updateStatuses.removeFirst()
        }
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lock.withLock { deletedQuery = query }
        return deleteStatus
    }
}

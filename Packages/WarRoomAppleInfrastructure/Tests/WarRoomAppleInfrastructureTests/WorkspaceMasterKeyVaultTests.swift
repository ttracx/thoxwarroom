import Foundation
import Security
import XCTest
@testable import WarRoomAppleInfrastructure
import WarRoomCore

final class WorkspaceMasterKeyVaultTests: XCTestCase {
    func testProvisionsWorkspaceScopedNonSynchronizingDeviceOnlyKey() async throws {
        let client = MasterKeyKeychainClient(
            copyResults: [.init(status: errSecItemNotFound, data: nil)]
        )
        let vault = KeychainWorkspaceMasterKeyVault(service: "test.master", keychain: client)
        let workspaceID = fixedWorkspaceID()

        let key = try await vault.masterKey(for: workspaceID, createIfMissing: true)

        XCTAssertEqual(key?.bitCount, 256)
        let attributes = try XCTUnwrap(client.addedAttributes)
        XCTAssertEqual(attributes[kSecAttrService as String] as? String, "test.master")
        XCTAssertEqual(
            attributes[kSecAttrAccount as String] as? String,
            "workspace:\(workspaceID.rawValue.uuidString.lowercased()):master:v1"
        )
        XCTAssertEqual(attributes[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(
            attributes[kSecAttrAccessible as String] as! CFString,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        )
        XCTAssertEqual((attributes[kSecValueData as String] as? Data)?.count, 32)
    }

    func testNormalReadNeverCreatesMissingKey() async throws {
        let client = MasterKeyKeychainClient(
            copyResults: [.init(status: errSecItemNotFound, data: nil)]
        )
        let vault = KeychainWorkspaceMasterKeyVault(service: "test.master", keychain: client)

        let key = try await vault.masterKey(for: fixedWorkspaceID(), createIfMissing: false)
        XCTAssertNil(key)
        XCTAssertNil(client.addedAttributes)
    }

    func testDuplicateProvisionReadsWinningKeyWithoutReplacement() async throws {
        let winner = Data(repeating: 7, count: 32)
        let client = MasterKeyKeychainClient(
            copyResults: [
                .init(status: errSecItemNotFound, data: nil),
                .init(status: errSecSuccess, data: winner),
            ],
            addStatus: errSecDuplicateItem
        )
        let vault = KeychainWorkspaceMasterKeyVault(service: "test.master", keychain: client)

        let optionalKey = try await vault.masterKey(
            for: fixedWorkspaceID(),
            createIfMissing: true
        )
        let key = try XCTUnwrap(optionalKey)

        XCTAssertEqual(key.withUnsafeBytes { Data($0) }, winner)
        XCTAssertEqual(client.updateCallCount, 0)
    }

    func testRejectsInvalidStoredKeyAndMapsLockedDeviceWithoutSecrets() async throws {
        let invalid = KeychainWorkspaceMasterKeyVault(
            service: "test.master",
            keychain: MasterKeyKeychainClient(
                copyResults: [.init(status: errSecSuccess, data: Data(repeating: 1, count: 31))]
            )
        )
        do {
            _ = try await invalid.masterKey(for: fixedWorkspaceID(), createIfMissing: false)
            XCTFail("Expected invalid key")
        } catch {
            XCTAssertEqual(error as? WorkspaceMasterKeyVaultError, .invalidStoredKey)
            XCTAssertEqual(String(describing: error), "Workspace encryption key is unavailable.")
        }

        let locked = KeychainWorkspaceMasterKeyVault(
            service: "test.master",
            keychain: MasterKeyKeychainClient(
                copyResults: [.init(status: errSecInteractionNotAllowed, data: nil)]
            )
        )
        do {
            _ = try await locked.masterKey(for: fixedWorkspaceID(), createIfMissing: false)
            XCTFail("Expected locked Keychain")
        } catch {
            XCTAssertEqual(error as? WorkspaceMasterKeyVaultError, .interactionNotAllowed)
        }
    }

    func testDeleteIsIdempotentAndWorkspaceScoped() async throws {
        let client = MasterKeyKeychainClient(
            copyResults: [],
            deleteStatus: errSecItemNotFound
        )
        let workspaceID = fixedWorkspaceID()
        let vault = KeychainWorkspaceMasterKeyVault(service: "test.master", keychain: client)

        try await vault.deleteMasterKey(for: workspaceID)

        XCTAssertEqual(
            client.deletedQuery?[kSecAttrAccount as String] as? String,
            "workspace:\(workspaceID.rawValue.uuidString.lowercased()):master:v1"
        )
    }

    private func fixedWorkspaceID() -> WorkspaceID {
        WorkspaceID(rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!)
    }
}

private final class MasterKeyKeychainClient: KeychainItemClient, @unchecked Sendable {
    private let lock = NSLock()
    private var copyResults: [KeychainCopyResult]
    private let addStatus: OSStatus
    private let deleteStatus: OSStatus
    private(set) var addedAttributes: [String: Any]?
    private(set) var deletedQuery: [String: Any]?
    private(set) var updateCallCount = 0

    init(
        copyResults: [KeychainCopyResult],
        addStatus: OSStatus = errSecSuccess,
        deleteStatus: OSStatus = errSecSuccess
    ) {
        self.copyResults = copyResults
        self.addStatus = addStatus
        self.deleteStatus = deleteStatus
    }

    func copyMatching(_ query: [String: Any]) -> KeychainCopyResult {
        lock.withLock {
            copyResults.isEmpty
                ? .init(status: errSecItemNotFound, data: nil)
                : copyResults.removeFirst()
        }
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.withLock { addedAttributes = attributes }
        return addStatus
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        lock.withLock { updateCallCount += 1 }
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lock.withLock { deletedQuery = query }
        return deleteStatus
    }
}

import Foundation
import Security
import XCTest
@testable import WarRoomAppleInfrastructure
import WarRoomCore

final class KeychainCredentialVaultTests: XCTestCase {
    func testAbsentCredentialReturnsNil() async throws {
        let client = MockKeychainClient(copyResult: .init(status: errSecItemNotFound, data: nil))
        let vault = KeychainCredentialVault(service: "test.service", keychain: client)

        let credential = try await vault.credential(for: workspaceID())

        XCTAssertNil(credential)
    }

    func testReadsCredentialWithoutExposingItThroughDescription() async throws {
        let secret = Data("private-token".utf8)
        let client = MockKeychainClient(copyResult: .init(status: errSecSuccess, data: secret))
        let vault = KeychainCredentialVault(service: "test.service", keychain: client)

        let storedCredential = try await vault.credential(for: workspaceID())
        let credential = try XCTUnwrap(storedCredential)

        XCTAssertEqual(credential.withUnsafeBytes { Data($0) }, secret)
        XCTAssertFalse(String(describing: credential).contains("private-token"))
    }

    func testStoreAddsWorkspaceScopedNonSynchronizingLockedDeviceItem() async throws {
        let client = MockKeychainClient(
            copyResult: .init(status: errSecItemNotFound, data: nil),
            updateStatuses: [errSecItemNotFound],
            addStatus: errSecSuccess
        )
        let workspaceID = workspaceID()
        let vault = KeychainCredentialVault(service: "test.service", keychain: client)

        try await vault.store(
            ProviderCredential(bytes: Data("private-token".utf8)),
            for: workspaceID
        )

        let added = try XCTUnwrap(client.addedAttributes)
        XCTAssertEqual(added[kSecClass as String] as! CFString, kSecClassGenericPassword)
        XCTAssertEqual(added[kSecAttrService as String] as? String, "test.service")
        XCTAssertEqual(
            added[kSecAttrAccount as String] as? String,
            "workspace:\(workspaceID.rawValue.uuidString.lowercased()):provider"
        )
        XCTAssertEqual(added[kSecValueData as String] as? Data, Data("private-token".utf8))
        XCTAssertEqual(
            added[kSecAttrAccessible as String] as! CFString,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        )
        XCTAssertEqual(added[kSecAttrSynchronizable as String] as? Bool, false)
    }

    func testStoreUpdatesExistingItemWithoutChangingAccessAttributes() async throws {
        let client = MockKeychainClient(
            copyResult: .init(status: errSecItemNotFound, data: nil),
            updateStatuses: [errSecSuccess]
        )
        let vault = KeychainCredentialVault(service: "test.service", keychain: client)

        try await vault.store(
            ProviderCredential(bytes: Data("replacement".utf8)),
            for: workspaceID()
        )

        XCTAssertNil(client.addedAttributes)
        XCTAssertEqual(client.lastUpdateAttributes?[kSecValueData as String] as? Data, Data("replacement".utf8))
        XCTAssertNil(client.lastUpdateAttributes?[kSecAttrAccessible as String])
    }

    func testDuplicateAddRetriesUpdate() async throws {
        let client = MockKeychainClient(
            copyResult: .init(status: errSecItemNotFound, data: nil),
            updateStatuses: [errSecItemNotFound, errSecSuccess],
            addStatus: errSecDuplicateItem
        )
        let vault = KeychainCredentialVault(service: "test.service", keychain: client)

        try await vault.store(
            ProviderCredential(bytes: Data("replacement".utf8)),
            for: workspaceID()
        )

        XCTAssertEqual(client.updateCallCount, 2)
    }

    func testRejectsEmptyCredentialAndMapsTypedErrors() async throws {
        let emptyClient = MockKeychainClient(copyResult: .init(status: errSecItemNotFound, data: nil))
        let emptyVault = KeychainCredentialVault(service: "test.service", keychain: emptyClient)
        do {
            try await emptyVault.store(ProviderCredential(bytes: Data()), for: workspaceID())
            XCTFail("Expected empty credential rejection")
        } catch {
            XCTAssertEqual(error as? KeychainCredentialVaultError, .emptyCredential)
        }

        let lockedClient = MockKeychainClient(
            copyResult: .init(status: errSecInteractionNotAllowed, data: nil)
        )
        let lockedVault = KeychainCredentialVault(service: "test.service", keychain: lockedClient)
        do {
            _ = try await lockedVault.credential(for: workspaceID())
            XCTFail("Expected locked Keychain error")
        } catch {
            XCTAssertEqual(error as? KeychainCredentialVaultError, .interactionNotAllowed)
        }
    }

    func testDeleteIsIdempotentAndWorkspaceScoped() async throws {
        let client = MockKeychainClient(
            copyResult: .init(status: errSecItemNotFound, data: nil),
            deleteStatus: errSecItemNotFound
        )
        let workspaceID = workspaceID()
        let vault = KeychainCredentialVault(service: "test.service", keychain: client)

        try await vault.deleteCredential(for: workspaceID)

        XCTAssertEqual(
            client.deletedQuery?[kSecAttrAccount as String] as? String,
            "workspace:\(workspaceID.rawValue.uuidString.lowercased()):provider"
        )
    }

    private func workspaceID() -> WorkspaceID {
        WorkspaceID(rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!)
    }
}

private final class MockKeychainClient: KeychainItemClient, @unchecked Sendable {
    private let lock = NSLock()
    private let configuredCopyResult: KeychainCopyResult
    private var configuredUpdateStatuses: [OSStatus]
    private let configuredAddStatus: OSStatus
    private let configuredDeleteStatus: OSStatus

    private(set) var addedAttributes: [String: Any]?
    private(set) var lastUpdateAttributes: [String: Any]?
    private(set) var deletedQuery: [String: Any]?
    private(set) var updateCallCount = 0

    init(
        copyResult: KeychainCopyResult,
        updateStatuses: [OSStatus] = [],
        addStatus: OSStatus = errSecSuccess,
        deleteStatus: OSStatus = errSecSuccess
    ) {
        self.configuredCopyResult = copyResult
        self.configuredUpdateStatuses = updateStatuses
        self.configuredAddStatus = addStatus
        self.configuredDeleteStatus = deleteStatus
    }

    func copyMatching(_ query: [String: Any]) -> KeychainCopyResult {
        configuredCopyResult
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.withLock { addedAttributes = attributes }
        return configuredAddStatus
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            updateCallCount += 1
            lastUpdateAttributes = attributes
            return configuredUpdateStatuses.isEmpty
                ? errSecSuccess
                : configuredUpdateStatuses.removeFirst()
        }
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lock.withLock { deletedQuery = query }
        return configuredDeleteStatus
    }
}

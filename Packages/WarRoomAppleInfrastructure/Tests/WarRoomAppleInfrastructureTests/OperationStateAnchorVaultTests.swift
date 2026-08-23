import Foundation
@preconcurrency import Security
import XCTest
@testable import WarRoomAppleInfrastructure

final class OperationStateAnchorVaultTests: XCTestCase {
    func testInitializesDeviceOnlyNonSynchronizingAnchorAndUpdatesCanonically() async throws {
        let client = OperationAnchorKeychainClient()
        let vault = KeychainOperationStateAnchorVault(
            service: "test.operation-anchor",
            keychain: client
        )

        let initialized = try await vault.initializeEmptyAnchor()
        XCTAssertEqual(initialized, .empty)
        let add = try XCTUnwrap(client.lastAdd)
        XCTAssertEqual(add[kSecAttrService as String] as? String, "test.operation-anchor")
        XCTAssertEqual(
            add[kSecAttrAccount as String] as? String,
            "global:audited-operations:v1"
        )
        XCTAssertEqual(
            add[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
        XCTAssertEqual(add[kSecAttrSynchronizable as String] as? Bool, false)

        let advanced = try StoredOperationStateAnchor.validated(
            revision: 7,
            stateDigest: Data(repeating: 0x7a, count: 32)
        )
        try await vault.store(advanced)
        let readBack = try await vault.anchor()
        XCTAssertEqual(readBack, advanced)
        XCTAssertEqual(client.updateCount, 1)
    }

    func testRejectsCorruptAnchorAndMapsLockedKeychainWithoutSensitiveDescription() async {
        let corruptClient = OperationAnchorKeychainClient(initialData: Data("invalid".utf8))
        let corruptVault = KeychainOperationStateAnchorVault(
            service: "test.operation-anchor",
            keychain: corruptClient
        )
        do {
            _ = try await corruptVault.anchor()
            XCTFail("Expected malformed anchor rejection")
        } catch {
            XCTAssertEqual(error as? OperationStateAnchorVaultError, .invalidStoredAnchor)
        }

        let lockedClient = OperationAnchorKeychainClient(
            copyStatus: errSecInteractionNotAllowed
        )
        let lockedVault = KeychainOperationStateAnchorVault(
            service: "test.operation-anchor",
            keychain: lockedClient
        )
        do {
            _ = try await lockedVault.anchor()
            XCTFail("Expected locked Keychain rejection")
        } catch {
            XCTAssertEqual(error as? OperationStateAnchorVaultError, .interactionNotAllowed)
        }
    }
}

private final class OperationAnchorKeychainClient: KeychainItemClient, @unchecked Sendable {
    private let lock = NSLock()
    private var itemData: Data?
    private let copyStatus: OSStatus
    private(set) var lastAdd: [String: Any]?
    private(set) var updateCount = 0

    init(initialData: Data? = nil, copyStatus: OSStatus = errSecSuccess) {
        itemData = initialData
        self.copyStatus = copyStatus
    }

    func copyMatching(_ query: [String: Any]) -> KeychainCopyResult {
        lock.withLock {
            guard copyStatus == errSecSuccess else {
                return KeychainCopyResult(status: copyStatus, data: nil)
            }
            guard let itemData else {
                return KeychainCopyResult(status: errSecItemNotFound, data: nil)
            }
            return KeychainCopyResult(status: errSecSuccess, data: itemData)
        }
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            guard itemData == nil else { return errSecDuplicateItem }
            lastAdd = attributes
            itemData = attributes[kSecValueData as String] as? Data
            return errSecSuccess
        }
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            guard itemData != nil else { return errSecItemNotFound }
            itemData = attributes[kSecValueData as String] as? Data
            updateCount += 1
            return errSecSuccess
        }
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lock.withLock {
            guard itemData != nil else { return errSecItemNotFound }
            itemData = nil
            return errSecSuccess
        }
    }
}

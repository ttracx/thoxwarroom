import Foundation
import Security
import XCTest
@testable import WarRoomAppleInfrastructure
import WarRoomCore

final class AuditHeadAnchorVaultTests: XCTestCase {
    func testInitializesWorkspaceScopedNonSynchronizingDeviceOnlyEmptyAnchor() async throws {
        let client = AuditAnchorKeychainClient()
        let vault = KeychainAuditHeadAnchorVault(service: "test.audit-anchor", keychain: client)
        let workspaceID = fixedWorkspaceID()

        let anchor = try await vault.initializeEmptyAnchor(for: workspaceID)

        XCTAssertEqual(anchor, .empty)
        let attributes = try XCTUnwrap(client.addedAttributes)
        XCTAssertEqual(attributes[kSecAttrService as String] as? String, "test.audit-anchor")
        XCTAssertEqual(
            attributes[kSecAttrAccount as String] as? String,
            "workspace:\(workspaceID.rawValue.uuidString.lowercased()):audit-head:v1"
        )
        XCTAssertEqual(attributes[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(
            attributes[kSecAttrAccessible as String] as! CFString,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        )
        let encoded = try XCTUnwrap(attributes[kSecValueData as String] as? Data)
        XCTAssertEqual(encoded.count, Data("THOX-WR-AUDIT-HEAD".utf8).count + 1 + 8 + 32)

        let nonCanonicalClient = AuditAnchorKeychainClient(initialData: encoded + Data([0]))
        let nonCanonicalVault = KeychainAuditHeadAnchorVault(
            service: "test.audit-anchor",
            keychain: nonCanonicalClient
        )
        do {
            _ = try await nonCanonicalVault.anchor(for: workspaceID)
            XCTFail("Expected trailing bytes to violate the canonical fixed-width format")
        } catch {
            XCTAssertEqual(error as? AuditHeadAnchorVaultError, .invalidStoredAnchor)
        }
    }

    func testCanonicalAnchorRoundTripsAndUpdateDoesNotRecreateMissingItem() async throws {
        let client = AuditAnchorKeychainClient()
        let vault = KeychainAuditHeadAnchorVault(service: "test.audit-anchor", keychain: client)
        let workspaceID = fixedWorkspaceID()
        _ = try await vault.initializeEmptyAnchor(for: workspaceID)
        let expected = try StoredAuditHeadAnchor.validated(
            entryCount: 7,
            headDigest: Data(repeating: 0x5a, count: 32)
        )

        try await vault.store(expected, for: workspaceID)
        let recovered = try await vault.anchor(for: workspaceID)
        XCTAssertEqual(recovered, expected)
        XCTAssertEqual(client.updateCallCount, 1)

        client.removeItem()
        do {
            try await vault.store(expected, for: workspaceID)
            XCTFail("Expected deleted anchor not to be silently recreated")
        } catch {
            XCTAssertEqual(error as? AuditHeadAnchorVaultError, .missingAnchor)
        }
        XCTAssertEqual(client.addCallCount, 1)
    }

    func testRejectsMalformedNonCanonicalAndOutOfBoundsAnchors() async throws {
        let client = AuditAnchorKeychainClient(initialData: Data("not-an-anchor".utf8))
        let vault = KeychainAuditHeadAnchorVault(service: "test.audit-anchor", keychain: client)

        do {
            _ = try await vault.anchor(for: fixedWorkspaceID())
            XCTFail("Expected malformed anchor rejection")
        } catch {
            XCTAssertEqual(error as? AuditHeadAnchorVaultError, .invalidStoredAnchor)
            XCTAssertEqual(String(describing: error), "Audit integrity anchor is unavailable.")
            XCTAssertEqual(String(reflecting: error), "AuditHeadAnchorVaultError(<redacted>)")
        }

        XCTAssertThrowsError(try StoredAuditHeadAnchor.validated(
            entryCount: StoredAuditHeadAnchor.maximumEntryCount + 1,
            headDigest: Data(repeating: 1, count: 32)
        )) { error in
            XCTAssertEqual(error as? AuditHeadAnchorVaultError, .invalidStoredAnchor)
        }
        XCTAssertThrowsError(try StoredAuditHeadAnchor.validated(
            entryCount: 0,
            headDigest: Data(repeating: 1, count: 32)
        ))
    }

    func testLockedReadAndFailedAddMapToTypedRedactedErrors() async throws {
        let lockedClient = AuditAnchorKeychainClient(copyStatus: errSecInteractionNotAllowed)
        let lockedVault = KeychainAuditHeadAnchorVault(
            service: "test.audit-anchor",
            keychain: lockedClient
        )
        do {
            _ = try await lockedVault.anchor(for: fixedWorkspaceID())
            XCTFail("Expected locked Keychain failure")
        } catch {
            XCTAssertEqual(error as? AuditHeadAnchorVaultError, .interactionNotAllowed)
            XCTAssertEqual(String(reflecting: error), "AuditHeadAnchorVaultError(<redacted>)")
        }

        let failedClient = AuditAnchorKeychainClient(addStatus: errSecAuthFailed)
        let failedVault = KeychainAuditHeadAnchorVault(
            service: "test.audit-anchor",
            keychain: failedClient
        )
        do {
            _ = try await failedVault.initializeEmptyAnchor(for: fixedWorkspaceID())
            XCTFail("Expected Keychain add failure")
        } catch {
            XCTAssertEqual(error as? AuditHeadAnchorVaultError, .authenticationFailed)
        }
    }

    private func fixedWorkspaceID() -> WorkspaceID {
        WorkspaceID(rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!)
    }
}

private final class AuditAnchorKeychainClient: KeychainItemClient, @unchecked Sendable {
    private let lock = NSLock()
    private var itemData: Data?
    private let copyStatus: OSStatus?
    private let addStatus: OSStatus
    private(set) var addedAttributes: [String: Any]?
    private(set) var addCallCount = 0
    private(set) var updateCallCount = 0

    init(
        initialData: Data? = nil,
        copyStatus: OSStatus? = nil,
        addStatus: OSStatus = errSecSuccess
    ) {
        itemData = initialData
        self.copyStatus = copyStatus
        self.addStatus = addStatus
    }

    func copyMatching(_ query: [String: Any]) -> KeychainCopyResult {
        lock.withLock {
            if let copyStatus {
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
            addCallCount += 1
            addedAttributes = attributes
            guard addStatus == errSecSuccess else { return addStatus }
            guard itemData == nil else { return errSecDuplicateItem }
            itemData = attributes[kSecValueData as String] as? Data
            return errSecSuccess
        }
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            updateCallCount += 1
            guard itemData != nil else { return errSecItemNotFound }
            itemData = attributes[kSecValueData as String] as? Data
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

    func removeItem() {
        lock.withLock { itemData = nil }
    }
}

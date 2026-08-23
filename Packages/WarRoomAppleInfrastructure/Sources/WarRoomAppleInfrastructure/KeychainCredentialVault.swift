import Foundation
@preconcurrency import Security
import WarRoomCore

/// Errors produced by the workspace-scoped Keychain credential vault.
public enum KeychainCredentialVaultError: Error, Equatable, Sendable {
    /// Empty credentials are never persisted.
    case emptyCredential
    /// Keychain returned a value with an unexpected type.
    case invalidStoredValue
    /// Keychain access is unavailable while the device is locked or policy denies interaction.
    case interactionNotAllowed
    /// Keychain rejected authentication for the requested operation.
    case authenticationFailed
    /// Keychain returned an unclassified status code.
    case unexpectedStatus(OSStatus)
}

/// Stores provider credentials as non-synchronizing, workspace-scoped generic passwords.
public struct KeychainCredentialVault: CredentialVault, Sendable {
    private static let defaultService = "ai.thox.warroom.provider-credentials"

    private let service: String
    private let keychain: any KeychainItemClient

    /// Creates a vault backed by the process's Apple Keychain access group.
    public init() {
        self.service = Self.defaultService
        self.keychain = SystemKeychainItemClient()
    }

    init(service: String, keychain: any KeychainItemClient) {
        self.service = service
        self.keychain = keychain
    }

    /// Reads a credential for one workspace, returning `nil` when none exists.
    public func credential(for workspaceID: WorkspaceID) async throws -> ProviderCredential? {
        let result = keychain.copyMatching(baseQuery(for: workspaceID))
        switch result.status {
        case errSecSuccess:
            guard let data = result.data else {
                throw KeychainCredentialVaultError.invalidStoredValue
            }
            return ProviderCredential(bytes: data)
        case errSecItemNotFound:
            return nil
        default:
            throw mappedError(result.status)
        }
    }

    /// Adds or atomically updates a credential for one workspace.
    public func store(
        _ credential: ProviderCredential,
        for workspaceID: WorkspaceID
    ) async throws {
        let data = credential.withUnsafeBytes { Data($0) }
        guard !data.isEmpty else {
            throw KeychainCredentialVaultError.emptyCredential
        }

        let query = baseQuery(for: workspaceID)
        let updateStatus = keychain.update(query, attributes: [
            kSecValueData as String: data,
        ])
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw mappedError(updateStatus)
        }

        var attributes = query
        attributes[kSecValueData as String] = data
        // ThisDeviceOnly prevents iCloud Keychain migration; WhenUnlocked is stricter
        // than after-first-unlock and avoids background disclosure on a locked device.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = keychain.add(attributes)
        if addStatus == errSecDuplicateItem {
            let retryStatus = keychain.update(query, attributes: [
                kSecValueData as String: data,
            ])
            guard retryStatus == errSecSuccess else {
                throw mappedError(retryStatus)
            }
            return
        }
        guard addStatus == errSecSuccess else {
            throw mappedError(addStatus)
        }
    }

    /// Deletes a workspace credential. Deleting an absent item is idempotent.
    public func deleteCredential(for workspaceID: WorkspaceID) async throws {
        let status = keychain.delete(baseQuery(for: workspaceID))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw mappedError(status)
        }
    }

    private func baseQuery(for workspaceID: WorkspaceID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "workspace:\(workspaceID.rawValue.uuidString.lowercased()):provider",
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    private func mappedError(_ status: OSStatus) -> KeychainCredentialVaultError {
        switch status {
        case errSecInteractionNotAllowed:
            return .interactionNotAllowed
        case errSecAuthFailed:
            return .authenticationFailed
        default:
            return .unexpectedStatus(status)
        }
    }
}

struct KeychainCopyResult {
    let status: OSStatus
    let data: Data?
}

protocol KeychainItemClient: Sendable {
    func copyMatching(_ query: [String: Any]) -> KeychainCopyResult
    func add(_ attributes: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

struct SystemKeychainItemClient: KeychainItemClient, @unchecked Sendable {
    func copyMatching(_ query: [String: Any]) -> KeychainCopyResult {
        var readQuery = query
        readQuery[kSecReturnData as String] = kCFBooleanTrue
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &result)
        return KeychainCopyResult(status: status, data: result as? Data)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

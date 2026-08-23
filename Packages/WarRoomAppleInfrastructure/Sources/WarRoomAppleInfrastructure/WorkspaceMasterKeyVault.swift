import CryptoKit
import Foundation
@preconcurrency import Security
import WarRoomCore

/// Redacted failures from workspace encryption-key storage.
public enum WorkspaceMasterKeyVaultError: Error, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible {
    case invalidStoredKey
    case interactionNotAllowed
    case authenticationFailed
    case unexpectedStatus(OSStatus)

    public var description: String { "Workspace encryption key is unavailable." }
    public var debugDescription: String { "WorkspaceMasterKeyVaultError(<redacted>)" }
}

protocol WorkspaceMasterKeyProviding: Sendable {
    func masterKey(for workspaceID: WorkspaceID, createIfMissing: Bool) async throws -> SymmetricKey?
    func deleteMasterKey(for workspaceID: WorkspaceID) async throws
}

/// Stores one non-synchronizing AES-256 master key per workspace in Apple Keychain.
public struct KeychainWorkspaceMasterKeyVault: WorkspaceMasterKeyProviding, Sendable {
    private static let defaultService = "ai.thox.warroom.workspace-encryption-keys"
    private static let keyByteCount = 32

    private let service: String
    private let keychain: any KeychainItemClient

    /// Creates a vault backed by the current app's Keychain access group.
    public init() {
        service = Self.defaultService
        keychain = SystemKeychainItemClient()
    }

    init(service: String, keychain: any KeychainItemClient) {
        self.service = service
        self.keychain = keychain
    }

    func masterKey(
        for workspaceID: WorkspaceID,
        createIfMissing: Bool
    ) async throws -> SymmetricKey? {
        switch readKeyData(for: workspaceID) {
        case .success(let data):
            return try key(from: data)
        case .failure(errSecItemNotFound) where createIfMissing:
            let candidate = SymmetricKey(size: .bits256)
            let candidateData = candidate.withUnsafeBytes { Data($0) }
            var attributes = baseQuery(for: workspaceID)
            attributes[kSecValueData as String] = candidateData
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

            let addStatus = keychain.add(attributes)
            if addStatus == errSecSuccess {
                return candidate
            }
            if addStatus == errSecDuplicateItem {
                switch readKeyData(for: workspaceID) {
                case .success(let winningData):
                    return try key(from: winningData)
                case .failure(let status):
                    throw mappedError(status)
                }
            }
            throw mappedError(addStatus)
        case .failure(errSecItemNotFound):
            return nil
        case .failure(let status):
            throw mappedError(status)
        }
    }

    func deleteMasterKey(for workspaceID: WorkspaceID) async throws {
        let status = keychain.delete(baseQuery(for: workspaceID))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw mappedError(status)
        }
    }

    private enum KeyReadResult {
        case success(Data)
        case failure(OSStatus)
    }

    private func readKeyData(for workspaceID: WorkspaceID) -> KeyReadResult {
        let result = keychain.copyMatching(baseQuery(for: workspaceID))
        guard result.status == errSecSuccess else { return .failure(result.status) }
        guard let data = result.data else { return .success(Data()) }
        return .success(data)
    }

    private func key(from data: Data) throws -> SymmetricKey {
        guard data.count == Self.keyByteCount else {
            throw WorkspaceMasterKeyVaultError.invalidStoredKey
        }
        return SymmetricKey(data: data)
    }

    private func baseQuery(for workspaceID: WorkspaceID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String:
                "workspace:\(workspaceID.rawValue.uuidString.lowercased()):master:v1",
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    private func mappedError(_ status: OSStatus) -> WorkspaceMasterKeyVaultError {
        switch status {
        case errSecInteractionNotAllowed: .interactionNotAllowed
        case errSecAuthFailed: .authenticationFailed
        default: .unexpectedStatus(status)
        }
    }
}

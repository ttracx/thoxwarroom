import Foundation
@preconcurrency import Security
import WarRoomCore

/// Non-sensitive failures from the OS-encrypted workspace deletion journal.
public enum KeychainWorkspaceDeletionJournalError: Error, Equatable, Sendable {
    case invalidStoredEntry
    case entryTooLarge
    case interactionNotAllowed
    case authenticationFailed
    case unexpectedStatus(OSStatus)
}

/// Stores the resumable deletion intent in the non-synchronizing Apple Keychain.
///
/// The journal uses a key independent of each workspace master key, so deleting a
/// workspace key cannot make deletion progress unreadable on either iOS or macOS.
public struct KeychainWorkspaceDeletionJournal: WorkspaceDeletionJournal, Sendable {
    private static let defaultService = "ai.thox.warroom.workspace-deletion-journal"
    private static let account = "pending:v1"
    private static let maximumEntryBytes = 1_024

    private let service: String
    private let keychain: any KeychainItemClient

    public init() {
        service = Self.defaultService
        keychain = SystemKeychainItemClient()
    }

    init(service: String, keychain: any KeychainItemClient) {
        self.service = service
        self.keychain = keychain
    }

    public func pendingEntry() async throws -> WorkspaceDeletionJournalEntry? {
        let result = keychain.copyMatching(baseQuery)
        switch result.status {
        case errSecSuccess:
            guard let data = result.data,
                  !data.isEmpty,
                  data.count <= Self.maximumEntryBytes,
                  let entry = try? JSONDecoder().decode(WorkspaceDeletionJournalEntry.self, from: data) else {
                throw KeychainWorkspaceDeletionJournalError.invalidStoredEntry
            }
            return entry
        case errSecItemNotFound:
            return nil
        default:
            throw mappedError(result.status)
        }
    }

    public func save(_ entry: WorkspaceDeletionJournalEntry) async throws {
        let data = try Self.makeEncoder().encode(entry)
        guard data.count <= Self.maximumEntryBytes else {
            throw KeychainWorkspaceDeletionJournalError.entryTooLarge
        }

        let updateStatus = keychain.update(baseQuery, attributes: [
            kSecValueData as String: data,
        ])
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw mappedError(updateStatus) }

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = keychain.add(attributes)
        if addStatus == errSecDuplicateItem {
            let retryStatus = keychain.update(baseQuery, attributes: [
                kSecValueData as String: data,
            ])
            guard retryStatus == errSecSuccess else { throw mappedError(retryStatus) }
            return
        }
        guard addStatus == errSecSuccess else { throw mappedError(addStatus) }
    }

    public func clear() async throws {
        let status = keychain.delete(baseQuery)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw mappedError(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func mappedError(_ status: OSStatus) -> KeychainWorkspaceDeletionJournalError {
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

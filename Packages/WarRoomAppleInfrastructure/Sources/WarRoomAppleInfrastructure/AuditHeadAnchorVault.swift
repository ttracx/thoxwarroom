import Foundation
@preconcurrency import Security
import WarRoomCore

/// Redacted failures from the rollback-resistant audit-head anchor boundary.
enum AuditHeadAnchorVaultError: Error, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible {
    case invalidStoredAnchor
    case missingAnchor
    case interactionNotAllowed
    case authenticationFailed
    case unexpectedStatus(OSStatus)

    var description: String { "Audit integrity anchor is unavailable." }
    var debugDescription: String { "AuditHeadAnchorVaultError(<redacted>)" }
}

struct StoredAuditHeadAnchor: Equatable, Sendable {
    static let schemaVersion: UInt8 = 1
    static let maximumEntryCount: UInt64 = 10_000
    static let digestByteCount = 32

    let schemaVersion: UInt8
    let entryCount: UInt64
    let headDigest: Data

    static var empty: StoredAuditHeadAnchor {
        StoredAuditHeadAnchor(
            schemaVersion: schemaVersion,
            entryCount: 0,
            headDigest: Data(repeating: 0, count: digestByteCount)
        )
    }

    static func validated(entryCount: UInt64, headDigest: Data) throws
        -> StoredAuditHeadAnchor {
        guard entryCount <= maximumEntryCount,
              headDigest.count == digestByteCount,
              entryCount != 0 || headDigest == empty.headDigest else {
            throw AuditHeadAnchorVaultError.invalidStoredAnchor
        }
        return StoredAuditHeadAnchor(
            schemaVersion: schemaVersion,
            entryCount: entryCount,
            headDigest: headDigest
        )
    }
}

protocol AuditHeadAnchorProviding: Sendable {
    func anchor(for workspaceID: WorkspaceID) async throws -> StoredAuditHeadAnchor?
    func initializeEmptyAnchor(for workspaceID: WorkspaceID) async throws
        -> StoredAuditHeadAnchor
    func store(_ anchor: StoredAuditHeadAnchor, for workspaceID: WorkspaceID) async throws
}

/// Stores one non-synchronizing, device-only audit head per workspace.
///
/// Keychain protects the small monotonic commitment independently from the encrypted
/// file ledger. Updates are intentionally add/update operations rather than a claimed
/// cross-process compare-and-swap; the owning audit-store actor serializes one instance.
struct KeychainAuditHeadAnchorVault: AuditHeadAnchorProviding, Sendable {
    private static let defaultService = "ai.thox.warroom.audit-head-anchors"
    private static let magic = Data("THOX-WR-AUDIT-HEAD".utf8)
    private static let encodedByteCount = magic.count + 1 + 8 + StoredAuditHeadAnchor.digestByteCount

    private let service: String
    private let keychain: any KeychainItemClient

    init() {
        service = Self.defaultService
        keychain = SystemKeychainItemClient()
    }

    init(service: String, keychain: any KeychainItemClient) {
        self.service = service
        self.keychain = keychain
    }

    func anchor(for workspaceID: WorkspaceID) async throws -> StoredAuditHeadAnchor? {
        try readAnchor(for: workspaceID)
    }

    func initializeEmptyAnchor(for workspaceID: WorkspaceID) async throws
        -> StoredAuditHeadAnchor {
        if let existing = try readAnchor(for: workspaceID) {
            return existing
        }

        var attributes = baseQuery(for: workspaceID)
        attributes[kSecValueData as String] = encode(.empty)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = keychain.add(attributes)
        if status == errSecSuccess {
            return .empty
        }
        if status == errSecDuplicateItem {
            guard let winner = try readAnchor(for: workspaceID) else {
                throw AuditHeadAnchorVaultError.missingAnchor
            }
            return winner
        }
        throw mappedError(status)
    }

    func store(_ anchor: StoredAuditHeadAnchor, for workspaceID: WorkspaceID) async throws {
        // Revalidate values supplied by the ledger boundary before committing them.
        _ = try StoredAuditHeadAnchor.validated(
            entryCount: anchor.entryCount,
            headDigest: anchor.headDigest
        )
        guard anchor.schemaVersion == StoredAuditHeadAnchor.schemaVersion else {
            throw AuditHeadAnchorVaultError.invalidStoredAnchor
        }
        let status = keychain.update(baseQuery(for: workspaceID), attributes: [
            kSecValueData as String: encode(anchor),
        ])
        guard status != errSecItemNotFound else {
            throw AuditHeadAnchorVaultError.missingAnchor
        }
        guard status == errSecSuccess else {
            throw mappedError(status)
        }
    }

    private func readAnchor(for workspaceID: WorkspaceID) throws -> StoredAuditHeadAnchor? {
        let result = keychain.copyMatching(baseQuery(for: workspaceID))
        switch result.status {
        case errSecSuccess:
            guard let data = result.data else {
                throw AuditHeadAnchorVaultError.invalidStoredAnchor
            }
            return try decode(data)
        case errSecItemNotFound:
            return nil
        default:
            throw mappedError(result.status)
        }
    }

    private func encode(_ anchor: StoredAuditHeadAnchor) -> Data {
        var value = Self.magic
        value.append(anchor.schemaVersion)
        var count = anchor.entryCount.bigEndian
        withUnsafeBytes(of: &count) { value.append(contentsOf: $0) }
        value.append(anchor.headDigest)
        return value
    }

    private func decode(_ data: Data) throws -> StoredAuditHeadAnchor {
        guard data.count == Self.encodedByteCount,
              data.prefix(Self.magic.count) == Self.magic else {
            throw AuditHeadAnchorVaultError.invalidStoredAnchor
        }
        var offset = data.index(data.startIndex, offsetBy: Self.magic.count)
        let version = data[offset]
        offset = data.index(after: offset)
        guard version == StoredAuditHeadAnchor.schemaVersion else {
            throw AuditHeadAnchorVaultError.invalidStoredAnchor
        }

        var count: UInt64 = 0
        let countEnd = data.index(offset, offsetBy: 8)
        for byte in data[offset..<countEnd] {
            count = (count << 8) | UInt64(byte)
        }
        offset = countEnd
        let digest = Data(data[offset...])
        return try StoredAuditHeadAnchor.validated(entryCount: count, headDigest: digest)
    }

    private func baseQuery(for workspaceID: WorkspaceID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String:
                "workspace:\(workspaceID.rawValue.uuidString.lowercased()):audit-head:v1",
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    private func mappedError(_ status: OSStatus) -> AuditHeadAnchorVaultError {
        switch status {
        case errSecInteractionNotAllowed: .interactionNotAllowed
        case errSecAuthFailed: .authenticationFailed
        default: .unexpectedStatus(status)
        }
    }
}

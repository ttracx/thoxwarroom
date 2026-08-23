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
    static let schemaVersion: UInt8 = 2
    static let legacySchemaVersion: UInt8 = 1
    static let maximumEntryCount: UInt64 = 10_000
    static let digestByteCount = 32

    let schemaVersion: UInt8
    let ledgerGeneration: UInt64
    let entryCount: UInt64
    let lifetimeEventCount: UInt64
    let headDigest: Data

    static var empty: StoredAuditHeadAnchor {
        StoredAuditHeadAnchor(
            schemaVersion: schemaVersion,
            ledgerGeneration: 0,
            entryCount: 0,
            lifetimeEventCount: 0,
            headDigest: Data(repeating: 0, count: digestByteCount)
        )
    }

    static func validated(entryCount: UInt64, headDigest: Data) throws
        -> StoredAuditHeadAnchor {
        try validated(
            ledgerGeneration: 0,
            entryCount: entryCount,
            lifetimeEventCount: entryCount,
            headDigest: headDigest
        )
    }

    static func validated(
        ledgerGeneration: UInt64,
        entryCount: UInt64,
        lifetimeEventCount: UInt64,
        headDigest: Data
    ) throws -> StoredAuditHeadAnchor {
        guard entryCount <= maximumEntryCount,
              entryCount <= lifetimeEventCount,
              headDigest.count == digestByteCount,
              entryCount != 0 || headDigest == empty.headDigest else {
            throw AuditHeadAnchorVaultError.invalidStoredAnchor
        }
        return StoredAuditHeadAnchor(
            schemaVersion: schemaVersion,
            ledgerGeneration: ledgerGeneration,
            entryCount: entryCount,
            lifetimeEventCount: lifetimeEventCount,
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
/// cross-process compare-and-swap; the audit store's workspace file lock serializes
/// cooperating instances and processes before this vault is read or updated.
struct KeychainAuditHeadAnchorVault: AuditHeadAnchorProviding, Sendable {
    private static let defaultService = "ai.thox.warroom.audit-head-anchors"
    private static let magic = Data("THOX-WR-AUDIT-HEAD".utf8)
    private static let legacyEncodedByteCount =
        magic.count + 1 + 8 + StoredAuditHeadAnchor.digestByteCount
    private static let encodedByteCount =
        magic.count + 1 + 8 + 8 + 8 + StoredAuditHeadAnchor.digestByteCount

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
            ledgerGeneration: anchor.ledgerGeneration,
            entryCount: anchor.entryCount,
            lifetimeEventCount: anchor.lifetimeEventCount,
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
        append(anchor.ledgerGeneration, to: &value)
        append(anchor.entryCount, to: &value)
        append(anchor.lifetimeEventCount, to: &value)
        value.append(anchor.headDigest)
        return value
    }

    private func append(_ integer: UInt64, to data: inout Data) {
        var value = integer.bigEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private func decode(_ data: Data) throws -> StoredAuditHeadAnchor {
        guard data.prefix(Self.magic.count) == Self.magic,
              data.count == Self.encodedByteCount || data.count == Self.legacyEncodedByteCount else {
            throw AuditHeadAnchorVaultError.invalidStoredAnchor
        }
        var offset = data.index(data.startIndex, offsetBy: Self.magic.count)
        let version = data[offset]
        offset = data.index(after: offset)
        if version == StoredAuditHeadAnchor.legacySchemaVersion,
           data.count == Self.legacyEncodedByteCount {
            let count = try readInteger(from: data, offset: &offset)
            let digest = Data(data[offset...])
            return try StoredAuditHeadAnchor.validated(entryCount: count, headDigest: digest)
        }
        guard version == StoredAuditHeadAnchor.schemaVersion,
              data.count == Self.encodedByteCount else {
            throw AuditHeadAnchorVaultError.invalidStoredAnchor
        }
        let generation = try readInteger(from: data, offset: &offset)
        let count = try readInteger(from: data, offset: &offset)
        let lifetimeCount = try readInteger(from: data, offset: &offset)
        let digest = Data(data[offset...])
        return try StoredAuditHeadAnchor.validated(
            ledgerGeneration: generation,
            entryCount: count,
            lifetimeEventCount: lifetimeCount,
            headDigest: digest
        )
    }

    private func readInteger(from data: Data, offset: inout Data.Index) throws -> UInt64 {
        guard data.distance(from: offset, to: data.endIndex) >= 8 else {
            throw AuditHeadAnchorVaultError.invalidStoredAnchor
        }
        let end = data.index(offset, offsetBy: 8)
        var value: UInt64 = 0
        for byte in data[offset..<end] {
            value = (value << 8) | UInt64(byte)
        }
        offset = end
        return value
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

import Foundation
@preconcurrency import Security
import WarRoomCore

enum WorkspaceAuditPolicyAnchorVaultError: Error, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible {
    case invalidStoredAnchor
    case missingAnchor
    case interactionNotAllowed
    case authenticationFailed
    case unexpectedStatus(OSStatus)

    var description: String { "Audit policy integrity anchor is unavailable." }
    var debugDescription: String { "WorkspaceAuditPolicyAnchorVaultError(<redacted>)" }
}

struct StoredWorkspaceAuditPolicyAnchor: Equatable, Sendable {
    static let schemaVersion: UInt8 = 1
    static let digestByteCount = 32

    let revision: UInt64
    let policyDigest: Data

    static var empty: StoredWorkspaceAuditPolicyAnchor {
        StoredWorkspaceAuditPolicyAnchor(
            revision: 0,
            policyDigest: Data(repeating: 0, count: digestByteCount)
        )
    }

    static func validated(
        revision: UInt64,
        policyDigest: Data
    ) throws -> StoredWorkspaceAuditPolicyAnchor {
        guard policyDigest.count == digestByteCount,
              revision != 0 || policyDigest == empty.policyDigest else {
            throw WorkspaceAuditPolicyAnchorVaultError.invalidStoredAnchor
        }
        return StoredWorkspaceAuditPolicyAnchor(
            revision: revision,
            policyDigest: policyDigest
        )
    }
}

protocol WorkspaceAuditPolicyAnchorProviding: Sendable {
    func anchor(for workspaceID: WorkspaceID) async throws
        -> StoredWorkspaceAuditPolicyAnchor?
    func initializeEmptyAnchor(for workspaceID: WorkspaceID) async throws
        -> StoredWorkspaceAuditPolicyAnchor
    func store(
        _ anchor: StoredWorkspaceAuditPolicyAnchor,
        for workspaceID: WorkspaceID
    ) async throws
}

/// Device-only, non-synchronizing monotonic commitments for encrypted policy records.
struct KeychainWorkspaceAuditPolicyAnchorVault:
    WorkspaceAuditPolicyAnchorProviding, Sendable {
    private static let defaultService = "ai.thox.warroom.audit-policy-anchors"
    private static let magic = Data("THOX-WR-AUDIT-POLICY".utf8)
    private static let encodedByteCount = magic.count + 1 + 8
        + StoredWorkspaceAuditPolicyAnchor.digestByteCount

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

    func anchor(for workspaceID: WorkspaceID) async throws
        -> StoredWorkspaceAuditPolicyAnchor? {
        try readAnchor(for: workspaceID)
    }

    func initializeEmptyAnchor(for workspaceID: WorkspaceID) async throws
        -> StoredWorkspaceAuditPolicyAnchor {
        if let existing = try readAnchor(for: workspaceID) { return existing }
        var attributes = baseQuery(for: workspaceID)
        attributes[kSecValueData as String] = encode(.empty)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = keychain.add(attributes)
        if status == errSecSuccess { return .empty }
        if status == errSecDuplicateItem {
            guard let winner = try readAnchor(for: workspaceID) else {
                throw WorkspaceAuditPolicyAnchorVaultError.missingAnchor
            }
            return winner
        }
        throw mappedError(status)
    }

    func store(
        _ anchor: StoredWorkspaceAuditPolicyAnchor,
        for workspaceID: WorkspaceID
    ) async throws {
        _ = try StoredWorkspaceAuditPolicyAnchor.validated(
            revision: anchor.revision,
            policyDigest: anchor.policyDigest
        )
        let status = keychain.update(baseQuery(for: workspaceID), attributes: [
            kSecValueData as String: encode(anchor),
        ])
        guard status != errSecItemNotFound else {
            throw WorkspaceAuditPolicyAnchorVaultError.missingAnchor
        }
        guard status == errSecSuccess else { throw mappedError(status) }
    }

    private func readAnchor(for workspaceID: WorkspaceID) throws
        -> StoredWorkspaceAuditPolicyAnchor? {
        let result = keychain.copyMatching(baseQuery(for: workspaceID))
        switch result.status {
        case errSecSuccess:
            guard let data = result.data else {
                throw WorkspaceAuditPolicyAnchorVaultError.invalidStoredAnchor
            }
            return try decode(data)
        case errSecItemNotFound:
            return nil
        default:
            throw mappedError(result.status)
        }
    }

    private func encode(_ anchor: StoredWorkspaceAuditPolicyAnchor) -> Data {
        var data = Self.magic
        data.append(StoredWorkspaceAuditPolicyAnchor.schemaVersion)
        var revision = anchor.revision.bigEndian
        withUnsafeBytes(of: &revision) { data.append(contentsOf: $0) }
        data.append(anchor.policyDigest)
        return data
    }

    private func decode(_ data: Data) throws -> StoredWorkspaceAuditPolicyAnchor {
        guard data.count == Self.encodedByteCount,
              data.prefix(Self.magic.count) == Self.magic else {
            throw WorkspaceAuditPolicyAnchorVaultError.invalidStoredAnchor
        }
        var offset = data.index(data.startIndex, offsetBy: Self.magic.count)
        guard data[offset] == StoredWorkspaceAuditPolicyAnchor.schemaVersion else {
            throw WorkspaceAuditPolicyAnchorVaultError.invalidStoredAnchor
        }
        offset = data.index(after: offset)
        let end = data.index(offset, offsetBy: 8)
        var revision: UInt64 = 0
        for byte in data[offset..<end] {
            revision = (revision << 8) | UInt64(byte)
        }
        return try StoredWorkspaceAuditPolicyAnchor.validated(
            revision: revision,
            policyDigest: Data(data[end...])
        )
    }

    private func baseQuery(for workspaceID: WorkspaceID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String:
                "workspace:\(workspaceID.rawValue.uuidString.lowercased()):audit-policy:v1",
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    private func mappedError(_ status: OSStatus) -> WorkspaceAuditPolicyAnchorVaultError {
        switch status {
        case errSecInteractionNotAllowed: .interactionNotAllowed
        case errSecAuthFailed: .authenticationFailed
        default: .unexpectedStatus(status)
        }
    }
}

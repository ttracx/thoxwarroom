import Foundation
@preconcurrency import Security

enum OperationStateAnchorVaultError: Error, Equatable, Sendable {
    case invalidStoredAnchor
    case missingAnchor
    case interactionNotAllowed
    case authenticationFailed
    case unexpectedStatus(OSStatus)
}

struct StoredOperationStateAnchor: Equatable, Sendable {
    static let schemaVersion: UInt8 = 1
    static let digestByteCount = 32

    let revision: UInt64
    let stateDigest: Data

    static var empty: StoredOperationStateAnchor {
        StoredOperationStateAnchor(
            revision: 0,
            stateDigest: Data(repeating: 0, count: digestByteCount)
        )
    }

    static func validated(
        revision: UInt64,
        stateDigest: Data
    ) throws -> StoredOperationStateAnchor {
        guard stateDigest.count == digestByteCount,
              revision != 0 || stateDigest == empty.stateDigest else {
            throw OperationStateAnchorVaultError.invalidStoredAnchor
        }
        return StoredOperationStateAnchor(revision: revision, stateDigest: stateDigest)
    }
}

protocol OperationStateAnchorProviding: Sendable {
    func anchor() async throws -> StoredOperationStateAnchor?
    func initializeEmptyAnchor() async throws -> StoredOperationStateAnchor
    func store(_ anchor: StoredOperationStateAnchor) async throws
}

/// Stores the global monotonic operation-state commitment in this device's Keychain.
/// The operation store's cross-process lock serializes cooperative reads and updates.
struct KeychainOperationStateAnchorVault: OperationStateAnchorProviding, Sendable {
    private static let defaultService = "ai.thox.warroom.operation-state-anchor"
    private static let account = "global:audited-operations:v1"
    private static let magic = Data("THOX-WR-OP-STATE".utf8)
    private static let encodedByteCount = magic.count + 1 + 8
        + StoredOperationStateAnchor.digestByteCount

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

    func anchor() async throws -> StoredOperationStateAnchor? {
        try readAnchor()
    }

    func initializeEmptyAnchor() async throws -> StoredOperationStateAnchor {
        if let existing = try readAnchor() { return existing }
        var attributes = baseQuery()
        attributes[kSecValueData as String] = encode(.empty)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = keychain.add(attributes)
        if status == errSecSuccess { return .empty }
        if status == errSecDuplicateItem {
            guard let winner = try readAnchor() else {
                throw OperationStateAnchorVaultError.missingAnchor
            }
            return winner
        }
        throw mappedError(status)
    }

    func store(_ anchor: StoredOperationStateAnchor) async throws {
        _ = try StoredOperationStateAnchor.validated(
            revision: anchor.revision,
            stateDigest: anchor.stateDigest
        )
        let status = keychain.update(baseQuery(), attributes: [
            kSecValueData as String: encode(anchor),
        ])
        guard status != errSecItemNotFound else {
            throw OperationStateAnchorVaultError.missingAnchor
        }
        guard status == errSecSuccess else { throw mappedError(status) }
    }

    private func readAnchor() throws -> StoredOperationStateAnchor? {
        let result = keychain.copyMatching(baseQuery())
        switch result.status {
        case errSecSuccess:
            guard let data = result.data else {
                throw OperationStateAnchorVaultError.invalidStoredAnchor
            }
            return try decode(data)
        case errSecItemNotFound:
            return nil
        default:
            throw mappedError(result.status)
        }
    }

    private func encode(_ anchor: StoredOperationStateAnchor) -> Data {
        var data = Self.magic
        data.append(StoredOperationStateAnchor.schemaVersion)
        var revision = anchor.revision.bigEndian
        withUnsafeBytes(of: &revision) { data.append(contentsOf: $0) }
        data.append(anchor.stateDigest)
        return data
    }

    private func decode(_ data: Data) throws -> StoredOperationStateAnchor {
        guard data.count == Self.encodedByteCount,
              data.prefix(Self.magic.count) == Self.magic else {
            throw OperationStateAnchorVaultError.invalidStoredAnchor
        }
        var offset = data.index(data.startIndex, offsetBy: Self.magic.count)
        guard data[offset] == StoredOperationStateAnchor.schemaVersion else {
            throw OperationStateAnchorVaultError.invalidStoredAnchor
        }
        offset = data.index(after: offset)
        let integerEnd = data.index(offset, offsetBy: 8)
        var revision: UInt64 = 0
        for byte in data[offset..<integerEnd] {
            revision = (revision << 8) | UInt64(byte)
        }
        return try StoredOperationStateAnchor.validated(
            revision: revision,
            stateDigest: Data(data[integerEnd...])
        )
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    private func mappedError(_ status: OSStatus) -> OperationStateAnchorVaultError {
        switch status {
        case errSecInteractionNotAllowed: .interactionNotAllowed
        case errSecAuthFailed: .authenticationFailed
        default: .unexpectedStatus(status)
        }
    }
}

import Foundation
import WarRoomAppleInfrastructure
import WarRoomCore

protocol EncryptedWorkspaceProfilePersisting: Sendable {
    func workspaceIDs() async throws -> [WorkspaceID]
    func loadProfilePayload(for workspaceID: WorkspaceID) async throws -> Data?
    func saveProfilePayload(
        _ payload: Data,
        for workspaceID: WorkspaceID,
        createdAt: Date,
        updatedAt: Date
    ) async throws
    func deleteWorkspace(_ workspaceID: WorkspaceID) async throws
}

struct UnavailableEncryptedWorkspaceProfilePersistence: EncryptedWorkspaceProfilePersisting {
    func workspaceIDs() async throws -> [WorkspaceID] { throw WorkspaceOnboardingError.persistence }
    func loadProfilePayload(for workspaceID: WorkspaceID) async throws -> Data? {
        throw WorkspaceOnboardingError.persistence
    }
    func saveProfilePayload(
        _ payload: Data,
        for workspaceID: WorkspaceID,
        createdAt: Date,
        updatedAt: Date
    ) async throws {
        throw WorkspaceOnboardingError.persistence
    }
    func deleteWorkspace(_ workspaceID: WorkspaceID) async throws {
        throw WorkspaceOnboardingError.persistence
    }
}

/// Owns the concrete Apple encryption and ciphertext-store composition for profiles.
actor AppleEncryptedWorkspaceProfileRepository: EncryptedWorkspaceProfilePersisting {
    private static let profileCollection = try! WorkspaceDataCollection(validating: "profile")

    private let store: EncryptedWorkspaceFileDataStore
    private let codec: EncryptedWorkspaceRecordCodec

    init(
        store: EncryptedWorkspaceFileDataStore,
        codec: EncryptedWorkspaceRecordCodec = EncryptedWorkspaceRecordCodec()
    ) {
        self.store = store
        self.codec = codec
    }

    static func makeDefault() throws -> AppleEncryptedWorkspaceProfileRepository {
        try AppleEncryptedWorkspaceProfileRepository(store: EncryptedWorkspaceFileDataStore())
    }

    func workspaceIDs() async throws -> [WorkspaceID] {
        try await store.workspaceIDs()
    }

    func loadProfilePayload(for workspaceID: WorkspaceID) async throws -> Data? {
        guard let record = try await store.record(
            id: recordID(for: workspaceID),
            in: workspaceID
        ) else { return nil }
        guard record.collection == Self.profileCollection else {
            throw WorkspaceOnboardingError.persistence
        }
        return try await codec.open(record)
    }

    func saveProfilePayload(
        _ payload: Data,
        for workspaceID: WorkspaceID,
        createdAt: Date,
        updatedAt: Date
    ) async throws {
        let id = recordID(for: workspaceID)
        let existing = try await store.record(id: id, in: workspaceID)
        if existing == nil {
            // Key creation is deliberately separate from sealing so missing key
            // material can never be silently recreated over existing ciphertext.
            try await codec.provisionMasterKey(for: workspaceID)
        }
        let record = try await codec.seal(
            payload,
            workspaceID: workspaceID,
            collection: Self.profileCollection,
            recordID: id,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        try await store.save(record)
    }

    func deleteWorkspace(_ workspaceID: WorkspaceID) async throws {
        // Cryptographic erasure is first and idempotent. If file cleanup fails,
        // the remaining ciphertext is unrecoverable and the selector is preserved
        // by the service so cleanup can be retried.
        try await codec.deleteMasterKey(for: workspaceID)
        try await store.deleteWorkspace(id: workspaceID)
    }

    private func recordID(for workspaceID: WorkspaceID) -> EncryptedWorkspaceRecordID {
        EncryptedWorkspaceRecordID(rawValue: workspaceID.rawValue)
    }
}

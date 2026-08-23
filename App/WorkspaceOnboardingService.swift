import Foundation
import WarRoomAppleInfrastructure
import WarRoomCore

@MainActor
protocol WorkspaceOnboardingServicing {
    func loadConfiguration() async throws -> WorkspaceProfile?
    func loadConfigurations() async throws -> [WorkspaceProfile]
    func selectConfiguration(_ workspaceID: WorkspaceID) async throws -> WorkspaceProfile
    func saveConfiguration(from draft: WorkspaceDraft) async throws -> WorkspaceProfile
    func deleteConfiguration() async throws
}

extension WorkspaceOnboardingServicing {
    func loadConfigurations() async throws -> [WorkspaceProfile] {
        try await loadConfiguration().map { [$0] } ?? []
    }

    func selectConfiguration(_ workspaceID: WorkspaceID) async throws -> WorkspaceProfile {
        guard let profile = try await loadConfiguration(), profile.id == workspaceID else {
            throw WorkspaceOnboardingError.persistence
        }
        return profile
    }
}

enum WorkspaceOnboardingError: LocalizedError {
    case validation(String)
    case persistence
    case deletionJournalUnavailable
    case deletionPending(WorkspaceDeletionStage)

    var errorDescription: String? {
        switch self {
        case .validation(let message): message
        case .persistence: "Workspace configuration is unavailable on this device."
        case .deletionJournalUnavailable:
            "Secure workspace removal state is unavailable. No workspace data was removed."
        case .deletionPending(let stage):
            switch stage {
            case .credentialDeletionPending:
                "Workspace removal is waiting for secure credential access. Unlock this device and try again."
            case .encryptedWorkspaceDeletionPending:
                "Workspace removal is waiting for encrypted data cleanup. Try again."
            case .selectorCleanupPending:
                "Workspace removal is waiting for local state cleanup. Try again."
            }
        }
    }
}

private struct StoredWorkspaceProfileV1: Codable, Equatable, Sendable {
    struct HostedGrant: Codable, Equatable, Sendable {
        let policyVersion: UInt16
        let grantedAtMilliseconds: Int64
    }

    let schemaVersion: UInt16
    let id: WorkspaceID
    let displayName: String
    let canonicalEndpoint: String
    let boundary: NetworkBoundary
    let providerID: ProviderID
    let hostedGrant: HostedGrant?
    let createdAtMilliseconds: Int64
    let updatedAtMilliseconds: Int64

    init(profile: WorkspaceProfile, hostedGrant: HostedGrant?) throws {
        schemaVersion = 1
        id = profile.id
        displayName = profile.displayName
        canonicalEndpoint = profile.endpoint.url.absoluteString
        boundary = profile.endpoint.boundary
        providerID = profile.provider.id
        self.hostedGrant = hostedGrant
        createdAtMilliseconds = try Self.milliseconds(profile.createdAt)
        updatedAtMilliseconds = try Self.milliseconds(profile.updatedAt)
    }

    private static func milliseconds(_ date: Date) throws -> Int64 {
        let value = date.timeIntervalSince1970 * 1_000
        guard value.isFinite,
              value > Double(Int64.min),
              value < Double(Int64.max) else {
            throw WorkspaceOnboardingError.persistence
        }
        return Int64(value.rounded(.towardZero))
    }
}

/// Persists only encrypted workspace metadata. Credentials remain in Keychain,
/// and provider capabilities are reconstructed from current trusted app code.
@MainActor
final class EncryptedWorkspaceOnboardingService: WorkspaceOnboardingServicing {
    private let defaults: UserDefaults
    private let legacyKey: String
    private let activeWorkspaceKey: String
    private let credentialVault: any CredentialVault
    private let persistence: any EncryptedWorkspaceProfilePersisting
    private let deletionJournal: any WorkspaceDeletionJournal
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let legacyDecoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        key: String = "workspace.profile.v1",
        activeWorkspaceKey: String = "workspace.active.v2",
        credentialVault: any CredentialVault = KeychainCredentialVault(),
        persistence: (any EncryptedWorkspaceProfilePersisting)? = nil,
        deletionJournal: any WorkspaceDeletionJournal = KeychainWorkspaceDeletionJournal()
    ) {
        self.defaults = defaults
        legacyKey = key
        self.activeWorkspaceKey = activeWorkspaceKey
        self.credentialVault = credentialVault
        self.deletionJournal = deletionJournal
        if let persistence {
            self.persistence = persistence
        } else {
            self.persistence = (try? AppleEncryptedWorkspaceProfileRepository.makeDefault())
                ?? UnavailableEncryptedWorkspaceProfilePersistence()
        }
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    func loadConfiguration() async throws -> WorkspaceProfile? {
        (try await loadConfigurations()).first
    }

    func loadConfigurations() async throws -> [WorkspaceProfile] {
        do {
            try await resumePendingDeletionIfNeeded()
            let repository = persistence
            var encryptedIDs = try await repository.workspaceIDs()
            if encryptedIDs.isEmpty, let migrated = try await migrateLegacyProfileIfPresent(
                using: repository
            ) {
                encryptedIDs = [migrated.id]
            }
            var profiles: [WorkspaceProfile] = []
            profiles.reserveCapacity(encryptedIDs.count)
            for encryptedID in encryptedIDs {
                try Task.checkCancellation()
                guard let payload = try await repository.loadProfilePayload(for: encryptedID) else {
                    throw WorkspaceOnboardingError.persistence
                }
                profiles.append(try decodeAndValidate(payload, expectedID: encryptedID))
            }
            guard Set(profiles.map(\.id)).count == profiles.count else {
                throw WorkspaceOnboardingError.persistence
            }
            guard !profiles.isEmpty else { return [] }
            let selectedID: WorkspaceID
            if let activeID = try activeWorkspaceID() {
                guard profiles.contains(where: { $0.id == activeID }) else {
                    throw WorkspaceOnboardingError.persistence
                }
                selectedID = activeID
            } else {
                selectedID = profiles.sorted(by: Self.profileSort).first!.id
                try persistActiveWorkspaceID(selectedID)
            }
            return profiles.sorted { left, right in
                if left.id == selectedID { return true }
                if right.id == selectedID { return false }
                return Self.profileSort(left, right)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as WorkspaceOnboardingError {
            throw error
        } catch {
            throw WorkspaceOnboardingError.persistence
        }
    }

    func selectConfiguration(_ workspaceID: WorkspaceID) async throws -> WorkspaceProfile {
        do {
            if let pending = try await pendingDeletionEntry() {
                throw WorkspaceOnboardingError.deletionPending(pending.stage)
            }
            guard let payload = try await persistence.loadProfilePayload(for: workspaceID) else {
                throw WorkspaceOnboardingError.persistence
            }
            let profile = try decodeAndValidate(payload, expectedID: workspaceID)
            try persistActiveWorkspaceID(workspaceID)
            return profile
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as WorkspaceOnboardingError {
            throw error
        } catch {
            throw WorkspaceOnboardingError.persistence
        }
    }

    func saveConfiguration(from draft: WorkspaceDraft) async throws -> WorkspaceProfile {
        do {
            if let pending = try await pendingDeletionEntry() {
                throw WorkspaceOnboardingError.deletionPending(pending.stage)
            }
            let endpoint = try EndpointValidator.validate(
                draft.endpoint,
                declaredBoundary: draft.boundary,
                hostedAccess: draft.hasHostedDataTransferConsent ? .granted : .denied,
                policy: draft.providerKind.endpointPolicy
            )
            let now = try canonicalDate(Date())
            let profile = try WorkspaceProfile(
                displayName: draft.name,
                endpoint: endpoint,
                provider: draft.providerKind.descriptor,
                createdAt: now,
                updatedAt: now
            )
            let grant = endpoint.boundary == .hosted
                ? StoredWorkspaceProfileV1.HostedGrant(
                    policyVersion: 1,
                    grantedAtMilliseconds: try milliseconds(now)
                )
                : nil
            let stored = try StoredWorkspaceProfileV1(profile: profile, hostedGrant: grant)
            let repository = persistence
            try await repository.saveProfilePayload(
                try encoder.encode(stored),
                for: profile.id,
                createdAt: profile.createdAt,
                updatedAt: profile.updatedAt
            )
            guard let readBack = try await repository.loadProfilePayload(for: profile.id),
                  try decodeAndValidate(readBack, expectedID: profile.id) == profile else {
                throw WorkspaceOnboardingError.persistence
            }
            try persistActiveWorkspaceID(profile.id)
            return profile
        } catch let error as EndpointValidationError {
            throw WorkspaceOnboardingError.validation(message(for: error))
        } catch let error as WorkspaceProfileError {
            throw WorkspaceOnboardingError.validation(message(for: error))
        } catch let error as WorkspaceOnboardingError {
            throw error
        } catch {
            throw WorkspaceOnboardingError.persistence
        }
    }

    func deleteConfiguration() async throws {
        do {
            if let pending = try await pendingDeletionEntry() {
                try await executeDeletion(pending)
                return
            }
            let selectedID = try activeWorkspaceID()
            let workspaceID: WorkspaceID
            if let selectedID {
                // Deletion remains retryable after cryptographic erasure even when
                // ciphertext cleanup failed during an earlier attempt.
                workspaceID = selectedID
            } else {
                guard let profile = try await loadConfiguration() else { return }
                workspaceID = profile.id
            }
            let intent = WorkspaceDeletionJournalEntry(
                workspaceID: workspaceID,
                stage: .credentialDeletionPending
            )
            do {
                try await deletionJournal.save(intent)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // No destructive operation begins unless its recovery intent is durable.
                throw WorkspaceOnboardingError.deletionJournalUnavailable
            }
            try await executeDeletion(intent)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as WorkspaceOnboardingError {
            throw error
        } catch {
            throw WorkspaceOnboardingError.persistence
        }
    }

    private func resumePendingDeletionIfNeeded() async throws {
        guard let pending = try await pendingDeletionEntry() else { return }
        try await executeDeletion(pending)
    }

    private func pendingDeletionEntry() async throws -> WorkspaceDeletionJournalEntry? {
        do {
            return try await deletionJournal.pendingEntry()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WorkspaceOnboardingError.deletionJournalUnavailable
        }
    }

    private func executeDeletion(_ intent: WorkspaceDeletionJournalEntry) async throws {
        var current = intent
        do {
            if current.stage != .selectorCleanupPending {
                // Before destructive phases, bind the journal back to the active
                // selector so a malformed or stale intent cannot target another workspace.
                guard try activeWorkspaceID() == current.workspaceID else {
                    throw WorkspaceOnboardingError.deletionPending(current.stage)
                }
            }
            while true {
                try Task.checkCancellation()
                switch current.stage {
                case .credentialDeletionPending:
                    // Credentials are first. A failure leaves profile key, ciphertext,
                    // selector, and the durable intent intact for a safe retry.
                    try await credentialVault.deleteCredential(for: current.workspaceID)
                    let next = WorkspaceDeletionJournalEntry(
                        workspaceID: current.workspaceID,
                        stage: .encryptedWorkspaceDeletionPending
                    )
                    try await deletionJournal.save(next)
                    current = next
                case .encryptedWorkspaceDeletionPending:
                    // Repository deletion is itself key-first and idempotent. Retrying
                    // can never provision a replacement key over leftover ciphertext.
                    try await persistence.deleteWorkspace(current.workspaceID)
                    let next = WorkspaceDeletionJournalEntry(
                        workspaceID: current.workspaceID,
                        stage: .selectorCleanupPending
                    )
                    try await deletionJournal.save(next)
                    current = next
                case .selectorCleanupPending:
                    try clearLocalSelectors()
                    try await selectFallbackWorkspaceIfPresent()
                    try await deletionJournal.clear()
                    return
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WorkspaceOnboardingError.deletionPending(current.stage)
        }
    }

    private func clearLocalSelectors() throws {
        defaults.removeObject(forKey: activeWorkspaceKey)
        defaults.removeObject(forKey: legacyKey)
        guard defaults.object(forKey: activeWorkspaceKey) == nil,
              defaults.object(forKey: legacyKey) == nil else {
            throw WorkspaceOnboardingError.deletionPending(.selectorCleanupPending)
        }
    }

    private func selectFallbackWorkspaceIfPresent() async throws {
        let remaining = try await persistence.workspaceIDs()
        guard let fallback = remaining.sorted(by: {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        }).first else { return }
        guard let payload = try await persistence.loadProfilePayload(for: fallback) else {
            throw WorkspaceOnboardingError.deletionPending(.selectorCleanupPending)
        }
        _ = try decodeAndValidate(payload, expectedID: fallback)
        try persistActiveWorkspaceID(fallback)
    }

    private func migrateLegacyProfileIfPresent(
        using repository: any EncryptedWorkspaceProfilePersisting
    ) async throws -> WorkspaceProfile? {
        guard let legacyData = defaults.data(forKey: legacyKey) else { return nil }
        let legacy = try legacyDecoder.decode(WorkspaceProfile.self, from: legacyData)
        guard let providerKind = WorkspaceProviderKind(providerID: legacy.provider.id) else {
            throw WorkspaceOnboardingError.persistence
        }
        let endpoint = try EndpointValidator.validate(
            legacy.endpoint.url.absoluteString,
            declaredBoundary: legacy.endpoint.boundary,
            hostedAccess: legacy.endpoint.boundary == .hosted ? .granted : .denied,
            policy: providerKind.endpointPolicy
        )
        let createdAt = try canonicalDate(legacy.createdAt)
        let updatedAt = try canonicalDate(legacy.updatedAt)
        let profile = try WorkspaceProfile(
            id: legacy.id,
            displayName: legacy.displayName,
            endpoint: endpoint,
            provider: providerKind.descriptor,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let grant = endpoint.boundary == .hosted
            ? StoredWorkspaceProfileV1.HostedGrant(
                policyVersion: 1,
                grantedAtMilliseconds: try milliseconds(updatedAt)
            )
            : nil
        let stored = try StoredWorkspaceProfileV1(profile: profile, hostedGrant: grant)
        try await repository.saveProfilePayload(
            try encoder.encode(stored),
            for: profile.id,
            createdAt: profile.createdAt,
            updatedAt: profile.updatedAt
        )
        guard let readBack = try await repository.loadProfilePayload(for: profile.id),
              try decodeAndValidate(readBack, expectedID: profile.id) == profile else {
            throw WorkspaceOnboardingError.persistence
        }
        try persistActiveWorkspaceID(profile.id)
        // Legacy plaintext is removed only after encrypted read-back and selector persistence.
        defaults.removeObject(forKey: legacyKey)
        return profile
    }

    private func decodeAndValidate(_ payload: Data, expectedID: WorkspaceID) throws -> WorkspaceProfile {
        let stored = try decoder.decode(StoredWorkspaceProfileV1.self, from: payload)
        guard stored.schemaVersion == 1,
              stored.id == expectedID,
              let providerKind = WorkspaceProviderKind(providerID: stored.providerID) else {
            throw WorkspaceOnboardingError.persistence
        }
        if stored.boundary == .hosted {
            guard let hostedGrant = stored.hostedGrant,
                  hostedGrant.policyVersion == 1,
                  hostedGrant.grantedAtMilliseconds >= stored.createdAtMilliseconds,
                  hostedGrant.grantedAtMilliseconds <= stored.updatedAtMilliseconds else {
                throw WorkspaceOnboardingError.persistence
            }
        } else if stored.hostedGrant != nil {
            throw WorkspaceOnboardingError.persistence
        }
        let endpoint = try EndpointValidator.validate(
            stored.canonicalEndpoint,
            declaredBoundary: stored.boundary,
            hostedAccess: stored.hostedGrant == nil ? .denied : .granted,
            policy: providerKind.endpointPolicy
        )
        return try WorkspaceProfile(
            id: stored.id,
            displayName: stored.displayName,
            endpoint: endpoint,
            provider: providerKind.descriptor,
            createdAt: Date(
                timeIntervalSince1970: Double(stored.createdAtMilliseconds) / 1_000
            ),
            updatedAt: Date(
                timeIntervalSince1970: Double(stored.updatedAtMilliseconds) / 1_000
            )
        )
    }

    private func canonicalDate(_ date: Date) throws -> Date {
        Date(timeIntervalSince1970: Double(try milliseconds(date)) / 1_000)
    }

    private func milliseconds(_ date: Date) throws -> Int64 {
        let value = date.timeIntervalSince1970 * 1_000
        guard value.isFinite,
              value > Double(Int64.min),
              value < Double(Int64.max) else {
            throw WorkspaceOnboardingError.persistence
        }
        return Int64(value.rounded(.towardZero))
    }

    private func activeWorkspaceID() throws -> WorkspaceID? {
        guard let value = defaults.string(forKey: activeWorkspaceKey) else { return nil }
        guard value == value.lowercased(), let uuid = UUID(uuidString: value) else {
            throw WorkspaceOnboardingError.persistence
        }
        return WorkspaceID(rawValue: uuid)
    }

    private func persistActiveWorkspaceID(_ workspaceID: WorkspaceID) throws {
        let value = workspaceID.rawValue.uuidString.lowercased()
        defaults.set(value, forKey: activeWorkspaceKey)
        guard defaults.string(forKey: activeWorkspaceKey) == value else {
            throw WorkspaceOnboardingError.persistence
        }
    }

    private static func profileSort(_ left: WorkspaceProfile, _ right: WorkspaceProfile) -> Bool {
        if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
        return left.id.rawValue.uuidString < right.id.rawValue.uuidString
    }

    private func message(for error: WorkspaceProfileError) -> String {
        switch error {
        case .emptyDisplayName: "Enter a workspace name."
        case .displayNameTooLong: "Keep the workspace name to 80 characters or fewer."
        case .updatedBeforeCreation: "The workspace dates are invalid."
        }
    }

    private func message(for error: EndpointValidationError) -> String {
        switch error {
        case .emptyEndpoint: "Enter the workspace endpoint."
        case .containsWhitespace: "The endpoint cannot contain spaces."
        case .malformedURL, .missingHost, .invalidHost:
            "Enter a complete endpoint with a valid host, such as http://127.0.0.1."
        case .unsupportedScheme: "Use an HTTP or HTTPS endpoint."
        case .embeddedCredentials:
            "Do not put a username or password in the endpoint. Credentials belong in secure storage."
        case .queryNotAllowed, .fragmentNotAllowed:
            "The workspace endpoint cannot contain a query or fragment."
        case .pathTraversal: "The endpoint path cannot contain parent-directory segments."
        case .invalidPort: "Enter a valid endpoint port."
        case .portNotAllowed(let port, let scheme):
            "Port \(port) is not allowed for \(scheme.uppercased()) by the workspace security policy."
        case .boundaryMismatch(let declared, let detected):
            "This address appears to be \(detected.title.lowercased()), not \(declared.title.lowercased()). Choose the matching data boundary."
        case .insecurePrivateNetworkTransport: "Private-network workspaces require HTTPS."
        case .insecureHostedTransport: "Hosted workspaces require HTTPS."
        case .hostedAccessNotAuthorized: "Confirm hosted data transfer before saving this workspace."
        }
    }
}

import XCTest
import WarRoomCore
@testable import ThoxWarRoom

@MainActor
final class WorkspaceOnboardingModelTests: XCTestCase {
    func testLoadWithoutSavedProfileProducesExplicitEmptyState() async {
        let service = WorkspaceOnboardingServiceStub()
        let model = WorkspaceOnboardingModel(service: service)

        await model.load()

        XCTAssertEqual(model.phase, .empty)
        XCTAssertEqual(service.loadCount, 1)
    }

    func testChangingAwayFromHostedRevokesDraftConsent() {
        let model = WorkspaceOnboardingModel(service: WorkspaceOnboardingServiceStub())
        model.beginConfiguration()
        model.selectBoundary(.hosted)
        model.draft.hasHostedDataTransferConsent = true

        model.selectBoundary(.localMachine)

        XCTAssertFalse(model.draft.hasHostedDataTransferConsent)
    }

    func testValidationFailureReturnsToEditableForm() async {
        let service = WorkspaceOnboardingServiceStub(
            saveError: WorkspaceOnboardingError.validation("Confirm hosted data transfer.")
        )
        let model = WorkspaceOnboardingModel(service: service)
        model.beginConfiguration()

        await model.save()

        XCTAssertEqual(model.phase, .editing)
        XCTAssertEqual(model.validationMessage, "Confirm hosted data transfer.")
    }

    func testCompatibilityEntryRemainsDisabledForHostedOrigins() throws {
        let exact = try profile(endpoint: "https://webui.thox.ai")
        let path = try profile(endpoint: "https://webui.thox.ai/chat")
        let suffix = try profile(endpoint: "https://webui.thox.ai.evil.example")

        XCTAssertFalse(WorkspaceProfile.isHostedCompatibilityEnabled)
        XCTAssertFalse(exact.supportsHostedCompatibilityOrigin)
        XCTAssertFalse(path.supportsHostedCompatibilityOrigin)
        XCTAssertFalse(suffix.supportsHostedCompatibilityOrigin)
    }

    private func profile(endpoint rawEndpoint: String) throws -> WorkspaceProfile {
        let endpoint = try EndpointValidator.validate(
            rawEndpoint,
            declaredBoundary: .hosted,
            hostedAccess: .granted
        )
        return try WorkspaceProfile(
            displayName: "Hosted",
            endpoint: endpoint,
            provider: WorkspaceProviderKind.openWebUI.descriptor
        )
    }
}

@MainActor
final class EncryptedWorkspaceOnboardingServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var persistence: InMemoryEncryptedWorkspaceProfilePersistence!
    private var deletionJournal: InMemoryWorkspaceDeletionJournal!

    override func setUp() {
        super.setUp()
        suiteName = "ai.thox.warroom.onboarding-tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        persistence = InMemoryEncryptedWorkspaceProfilePersistence()
        deletionJournal = InMemoryWorkspaceDeletionJournal()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        persistence = nil
        deletionJournal = nil
        suiteName = nil
        super.tearDown()
    }

    func testLocalProfileMetadataRoundTripsAndDeletes() async throws {
        let vault = OnboardingCredentialVaultStub()
        let service = EncryptedWorkspaceOnboardingService(
            defaults: defaults,
            credentialVault: vault,
            persistence: persistence,
            deletionJournal: deletionJournal
        )
        let profile = try await service.saveConfiguration(
            from: WorkspaceDraft(
                name: "Local Lab",
                endpoint: "http://127.0.0.1",
                boundary: .localMachine
            )
        )

        XCTAssertEqual(profile.displayName, "Local Lab")
        XCTAssertEqual(profile.endpoint.boundary, .localMachine)
        let loadedProfile = try await service.loadConfiguration()
        XCTAssertEqual(loadedProfile, profile)
        XCTAssertNil(defaults.data(forKey: "workspace.profile.v1"))
        XCTAssertEqual(
            defaults.string(forKey: "workspace.active.v2"),
            profile.id.rawValue.uuidString.lowercased()
        )
        let savedPayload = await persistence.payload(for: profile.id)
        XCTAssertNotNil(savedPayload)

        try await service.deleteConfiguration()
        let deletedProfile = try await service.loadConfiguration()
        XCTAssertNil(deletedProfile)
        let deletedIDs = await vault.deletedIDs
        XCTAssertEqual(deletedIDs, [profile.id])
        let deletedWorkspaceIDs = await persistence.deletedWorkspaceIDs
        XCTAssertEqual(deletedWorkspaceIDs, [profile.id])
    }

    func testMultipleEncryptedWorkspacesCanBeListedSelectedAndDeletedIndependently() async throws {
        let vault = OnboardingCredentialVaultStub()
        let service = EncryptedWorkspaceOnboardingService(
            defaults: defaults,
            credentialVault: vault,
            persistence: persistence,
            deletionJournal: deletionJournal
        )
        let first = try await service.saveConfiguration(
            from: WorkspaceDraft(
                name: "Local Research",
                endpoint: "http://127.0.0.1",
                boundary: .localMachine
            )
        )
        let second = try await service.saveConfiguration(
            from: WorkspaceDraft(
                name: "Private Operations",
                endpoint: "https://10.0.0.8",
                providerKind: .hermes,
                boundary: .privateNetwork
            )
        )

        var profiles = try await service.loadConfigurations()
        let initiallyLoaded = try await service.loadConfiguration()
        XCTAssertEqual(profiles.map(\.id), [second.id, first.id])
        XCTAssertEqual(initiallyLoaded?.id, second.id)

        let selected = try await service.selectConfiguration(first.id)
        XCTAssertEqual(selected.id, first.id)
        profiles = try await service.loadConfigurations()
        XCTAssertEqual(profiles.map(\.id), [first.id, second.id])

        try await service.deleteConfiguration()

        profiles = try await service.loadConfigurations()
        let loadedAfterDeletion = try await service.loadConfiguration()
        XCTAssertEqual(profiles.map(\.id), [second.id])
        XCTAssertEqual(loadedAfterDeletion?.id, second.id)
        let deletedPayload = await persistence.payload(for: first.id)
        let retainedPayload = await persistence.payload(for: second.id)
        let deletedCredentialIDs = await vault.deletedIDs
        XCTAssertNil(deletedPayload)
        XCTAssertNotNil(retainedPayload)
        XCTAssertEqual(deletedCredentialIDs, [first.id])
    }

    func testSelectingUnknownWorkspaceFailsWithoutChangingActiveSelection() async throws {
        let service = EncryptedWorkspaceOnboardingService(
            defaults: defaults,
            persistence: persistence,
            deletionJournal: deletionJournal
        )
        let profile = try await service.saveConfiguration(
            from: WorkspaceDraft(name: "Local Lab", endpoint: "http://127.0.0.1")
        )

        do {
            _ = try await service.selectConfiguration(.make())
            XCTFail("Expected an unknown workspace selection to fail")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Workspace configuration is unavailable on this device."
            )
        }

        let loaded = try await service.loadConfiguration()
        XCTAssertEqual(loaded?.id, profile.id)
        XCTAssertEqual(
            defaults.string(forKey: "workspace.active.v2"),
            profile.id.rawValue.uuidString.lowercased()
        )
    }

    func testWorkspaceMetadataIsPreservedWhenCredentialDeletionFails() async throws {
        let vault = OnboardingCredentialVaultStub(deleteFails: true)
        let service = EncryptedWorkspaceOnboardingService(
            defaults: defaults,
            credentialVault: vault,
            persistence: persistence,
            deletionJournal: deletionJournal
        )
        let profile = try await service.saveConfiguration(
            from: WorkspaceDraft(name: "Local Lab", endpoint: "http://127.0.0.1")
        )

        do {
            try await service.deleteConfiguration()
            XCTFail("Expected credential deletion failure")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Workspace removal is waiting for secure credential access. Unlock this device and try again."
            )
        }

        let preservedPayload = await persistence.payload(for: profile.id)
        let pendingEntry = await deletionJournal.entry
        XCTAssertNotNil(preservedPayload)
        XCTAssertEqual(pendingEntry?.stage, .credentialDeletionPending)
        XCTAssertEqual(
            defaults.string(forKey: "workspace.active.v2"),
            profile.id.rawValue.uuidString.lowercased()
        )
    }

    func testCiphertextCleanupCanRetryAfterCryptographicErasure() async throws {
        let vault = OnboardingCredentialVaultStub()
        let retryingPersistence = InMemoryEncryptedWorkspaceProfilePersistence(
            deleteFailuresRemaining: 1
        )
        let service = EncryptedWorkspaceOnboardingService(
            defaults: defaults,
            credentialVault: vault,
            persistence: retryingPersistence,
            deletionJournal: deletionJournal
        )
        let profile = try await service.saveConfiguration(
            from: WorkspaceDraft(name: "Local Lab", endpoint: "http://127.0.0.1")
        )

        do {
            try await service.deleteConfiguration()
            XCTFail("Expected first ciphertext cleanup to fail")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Workspace removal is waiting for encrypted data cleanup. Try again."
            )
        }
        XCTAssertEqual(
            defaults.string(forKey: "workspace.active.v2"),
            profile.id.rawValue.uuidString.lowercased()
        )

        let resumedService = EncryptedWorkspaceOnboardingService(
            defaults: defaults,
            credentialVault: vault,
            persistence: retryingPersistence,
            deletionJournal: deletionJournal
        )
        let loadedAfterResume = try await resumedService.loadConfiguration()
        XCTAssertNil(loadedAfterResume)

        XCTAssertNil(defaults.string(forKey: "workspace.active.v2"))
        let deletedIDs = await vault.deletedIDs
        XCTAssertEqual(deletedIDs, [profile.id])
        let finalEntry = await deletionJournal.entry
        XCTAssertNil(finalEntry)
    }

    func testJournalCreationFailurePerformsNoDestructiveOperation() async throws {
        let vault = OnboardingCredentialVaultStub()
        let failingJournal = InMemoryWorkspaceDeletionJournal(saveFailureCalls: [1])
        let service = EncryptedWorkspaceOnboardingService(
            defaults: defaults,
            credentialVault: vault,
            persistence: persistence,
            deletionJournal: failingJournal
        )
        let profile = try await service.saveConfiguration(
            from: WorkspaceDraft(name: "Local Lab", endpoint: "http://127.0.0.1")
        )

        do {
            try await service.deleteConfiguration()
            XCTFail("Expected deletion journal creation to fail")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Secure workspace removal state is unavailable. No workspace data was removed."
            )
        }

        let deletedCredentials = await vault.deletedIDs
        let deletedWorkspaces = await persistence.deletedWorkspaceIDs
        let preservedPayload = await persistence.payload(for: profile.id)
        XCTAssertTrue(deletedCredentials.isEmpty)
        XCTAssertTrue(deletedWorkspaces.isEmpty)
        XCTAssertNotNil(preservedPayload)
        XCTAssertNotNil(defaults.string(forKey: "workspace.active.v2"))
    }

    func testFailedPhaseAdvanceReplaysCredentialDeletionWithoutDeletingCiphertextEarly() async throws {
        let vault = OnboardingCredentialVaultStub()
        let failingJournal = InMemoryWorkspaceDeletionJournal(saveFailureCalls: [2])
        let service = EncryptedWorkspaceOnboardingService(
            defaults: defaults,
            credentialVault: vault,
            persistence: persistence,
            deletionJournal: failingJournal
        )
        let profile = try await service.saveConfiguration(
            from: WorkspaceDraft(name: "Local Lab", endpoint: "http://127.0.0.1")
        )

        do {
            try await service.deleteConfiguration()
            XCTFail("Expected the first phase advance to fail")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Workspace removal is waiting for secure credential access. Unlock this device and try again."
            )
        }

        let preservedPayload = await persistence.payload(for: profile.id)
        let pendingAfterFailure = await failingJournal.entry
        XCTAssertNotNil(preservedPayload)
        XCTAssertEqual(pendingAfterFailure?.stage, .credentialDeletionPending)

        try await service.deleteConfiguration()

        let deletedCredentials = await vault.deletedIDs
        XCTAssertEqual(deletedCredentials, [profile.id, profile.id])
        let finalEntry = await failingJournal.entry
        XCTAssertNil(finalEntry)
        XCTAssertNil(defaults.string(forKey: "workspace.active.v2"))
    }

    func testHostedProfileRequiresSeparateConsent() async {
        let service = EncryptedWorkspaceOnboardingService(
            defaults: defaults,
            persistence: persistence,
            deletionJournal: deletionJournal
        )
        let draft = WorkspaceDraft(
            name: "Hosted Lab",
            endpoint: "https://example.com",
            boundary: .hosted,
            hasHostedDataTransferConsent: false
        )

        do {
            _ = try await service.saveConfiguration(from: draft)
            XCTFail("Expected hosted access without consent to fail")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Confirm hosted data transfer before saving this workspace."
            )
        }
        XCTAssertNil(defaults.data(forKey: "workspace.profile.v1"))
    }

    func testCredentialsInEndpointAreRejectedAndNeverPersisted() async {
        let service = EncryptedWorkspaceOnboardingService(
            defaults: defaults,
            persistence: persistence,
            deletionJournal: deletionJournal
        )
        let draft = WorkspaceDraft(
            name: "Unsafe",
            endpoint: "https://user:secret@example.com",
            boundary: .hosted,
            hasHostedDataTransferConsent: true
        )

        do {
            _ = try await service.saveConfiguration(from: draft)
            XCTFail("Expected an endpoint containing credentials to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("secure storage"))
        }
        XCTAssertNil(defaults.data(forKey: "workspace.profile.v1"))
    }

    func testBoundaryMismatchIsShownAndNeverPersisted() async {
        let service = EncryptedWorkspaceOnboardingService(
            defaults: defaults,
            persistence: persistence,
            deletionJournal: deletionJournal
        )
        let draft = WorkspaceDraft(
            name: "Wrong boundary",
            endpoint: "https://example.com",
            boundary: .privateNetwork
        )

        do {
            _ = try await service.saveConfiguration(from: draft)
            XCTFail("Expected a public endpoint declared private to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("hosted service"))
            XCTAssertTrue(error.localizedDescription.contains("private network"))
        }
        XCTAssertNil(defaults.data(forKey: "workspace.profile.v1"))
    }

    func testCorruptMetadataFailsWithoutDeletingEvidence() async {
        let service = EncryptedWorkspaceOnboardingService(
            defaults: defaults,
            persistence: persistence,
            deletionJournal: deletionJournal
        )
        let corruptData = Data("not-json".utf8)
        defaults.set(corruptData, forKey: "workspace.profile.v1")

        do {
            _ = try await service.loadConfiguration()
            XCTFail("Expected corrupt profile metadata to fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Workspace configuration is unavailable on this device.")
        }
        XCTAssertEqual(defaults.data(forKey: "workspace.profile.v1"), corruptData)
    }

    func testLegacyProfileMigratesOnlyAfterEncryptedReadBack() async throws {
        let endpoint = try EndpointValidator.validate(
            "http://127.0.0.1",
            declaredBoundary: .localMachine
        )
        let legacy = try WorkspaceProfile(
            displayName: "Legacy Lab",
            endpoint: endpoint,
            provider: WorkspaceProviderKind.openWebUI.descriptor,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        defaults.set(try JSONEncoder().encode(legacy), forKey: "workspace.profile.v1")
        let service = EncryptedWorkspaceOnboardingService(
            defaults: defaults,
            persistence: persistence,
            deletionJournal: deletionJournal
        )

        let migrated = try await service.loadConfiguration()

        XCTAssertEqual(migrated, legacy)
        XCTAssertNil(defaults.data(forKey: "workspace.profile.v1"))
        let encryptedPayload = await persistence.payload(for: legacy.id)
        XCTAssertNotNil(encryptedPayload)
    }

    func testLegacyProfileIsPreservedWhenEncryptedReadBackFails() async throws {
        let endpoint = try EndpointValidator.validate(
            "http://127.0.0.1",
            declaredBoundary: .localMachine
        )
        let legacy = try WorkspaceProfile(
            displayName: "Legacy Lab",
            endpoint: endpoint,
            provider: WorkspaceProviderKind.openWebUI.descriptor,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let legacyData = try JSONEncoder().encode(legacy)
        defaults.set(legacyData, forKey: "workspace.profile.v1")
        await persistence.setReadBackFails(true)
        let service = EncryptedWorkspaceOnboardingService(
            defaults: defaults,
            persistence: persistence,
            deletionJournal: deletionJournal
        )

        do {
            _ = try await service.loadConfiguration()
            XCTFail("Expected encrypted read-back failure")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Workspace configuration is unavailable on this device."
            )
        }

        XCTAssertEqual(defaults.data(forKey: "workspace.profile.v1"), legacyData)
        XCTAssertNil(defaults.string(forKey: "workspace.active.v2"))
        await persistence.setReadBackFails(false)
    }
}

private actor InMemoryEncryptedWorkspaceProfilePersistence: EncryptedWorkspaceProfilePersisting {
    private var payloads: [WorkspaceID: Data] = [:]
    private var readBackFails: Bool
    private var deleteFailuresRemaining: Int
    private(set) var deletedWorkspaceIDs: [WorkspaceID] = []

    init(readBackFails: Bool = false, deleteFailuresRemaining: Int = 0) {
        self.readBackFails = readBackFails
        self.deleteFailuresRemaining = deleteFailuresRemaining
    }

    func workspaceIDs() -> [WorkspaceID] {
        Array(payloads.keys)
    }

    func loadProfilePayload(for workspaceID: WorkspaceID) -> Data? {
        readBackFails ? nil : payloads[workspaceID]
    }

    func saveProfilePayload(
        _ payload: Data,
        for workspaceID: WorkspaceID,
        createdAt: Date,
        updatedAt: Date
    ) {
        payloads[workspaceID] = payload
    }

    func deleteWorkspace(_ workspaceID: WorkspaceID) throws {
        if deleteFailuresRemaining > 0 {
            deleteFailuresRemaining -= 1
            throw InMemoryEncryptedPersistenceError.injectedFailure
        }
        payloads.removeValue(forKey: workspaceID)
        deletedWorkspaceIDs.append(workspaceID)
    }

    func payload(for workspaceID: WorkspaceID) -> Data? {
        payloads[workspaceID]
    }

    func setReadBackFails(_ value: Bool) {
        readBackFails = value
    }
}

private enum InMemoryEncryptedPersistenceError: Error { case injectedFailure }

private actor InMemoryWorkspaceDeletionJournal: WorkspaceDeletionJournal {
    private(set) var entry: WorkspaceDeletionJournalEntry?
    private var saveCallCount = 0
    private var saveFailureCalls: Set<Int>

    init(
        entry: WorkspaceDeletionJournalEntry? = nil,
        saveFailureCalls: Set<Int> = []
    ) {
        self.entry = entry
        self.saveFailureCalls = saveFailureCalls
    }

    func pendingEntry() -> WorkspaceDeletionJournalEntry? { entry }

    func save(_ entry: WorkspaceDeletionJournalEntry) throws {
        saveCallCount += 1
        if saveFailureCalls.remove(saveCallCount) != nil {
            throw InMemoryWorkspaceDeletionJournalError.injectedFailure
        }
        self.entry = entry
    }

    func clear() { entry = nil }
}

private enum InMemoryWorkspaceDeletionJournalError: Error { case injectedFailure }

private actor OnboardingCredentialVaultStub: CredentialVault {
    private let deleteFails: Bool
    private(set) var deletedIDs: [WorkspaceID] = []

    init(deleteFails: Bool = false) {
        self.deleteFails = deleteFails
    }

    func credential(for workspaceID: WorkspaceID) -> ProviderCredential? { nil }
    func store(_ credential: ProviderCredential, for workspaceID: WorkspaceID) {}

    func deleteCredential(for workspaceID: WorkspaceID) throws {
        if deleteFails { throw OnboardingCredentialVaultError.unavailable }
        deletedIDs.append(workspaceID)
    }
}

private enum OnboardingCredentialVaultError: Error { case unavailable }

@MainActor
private final class WorkspaceOnboardingServiceStub: WorkspaceOnboardingServicing {
    private let loadedProfile: WorkspaceProfile?
    private let saveError: Error?
    private(set) var loadCount = 0

    init(loadedProfile: WorkspaceProfile? = nil, saveError: Error? = nil) {
        self.loadedProfile = loadedProfile
        self.saveError = saveError
    }

    func loadConfiguration() async throws -> WorkspaceProfile? {
        loadCount += 1
        return loadedProfile
    }

    func saveConfiguration(from draft: WorkspaceDraft) async throws -> WorkspaceProfile {
        if let saveError { throw saveError }
        let endpoint = try EndpointValidator.validate(
            "http://127.0.0.1",
            declaredBoundary: .localMachine
        )
        return try WorkspaceProfile(
            displayName: draft.name.isEmpty ? "Test" : draft.name,
            endpoint: endpoint,
            provider: ProviderDescriptor(
                id: ProviderID(rawValue: "test"),
                displayName: "Test",
                capabilities: []
            )
        )
    }

    func deleteConfiguration() async throws {}
}

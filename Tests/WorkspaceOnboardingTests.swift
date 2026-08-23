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
final class UserDefaultsWorkspaceOnboardingServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ai.thox.warroom.onboarding-tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testLocalProfileMetadataRoundTripsAndDeletes() async throws {
        let vault = OnboardingCredentialVaultStub()
        let service = UserDefaultsWorkspaceOnboardingService(
            defaults: defaults,
            credentialVault: vault
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
        let persistedText = String(
            decoding: defaults.data(forKey: "workspace.profile.v1") ?? Data(),
            as: UTF8.self
        ).lowercased()
        for prohibitedField in ["credential", "password", "secret", "token"] {
            XCTAssertFalse(persistedText.contains(prohibitedField), prohibitedField)
        }

        try await service.deleteConfiguration()
        let deletedProfile = try await service.loadConfiguration()
        XCTAssertNil(deletedProfile)
        let deletedIDs = await vault.deletedIDs
        XCTAssertEqual(deletedIDs, [profile.id])
    }

    func testWorkspaceMetadataIsPreservedWhenCredentialDeletionFails() async throws {
        let vault = OnboardingCredentialVaultStub(deleteFails: true)
        let service = UserDefaultsWorkspaceOnboardingService(
            defaults: defaults,
            credentialVault: vault
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
                "Workspace configuration is unavailable on this device."
            )
        }

        let preservedProfile = try await service.loadConfiguration()
        XCTAssertEqual(preservedProfile, profile)
    }

    func testHostedProfileRequiresSeparateConsent() async {
        let service = UserDefaultsWorkspaceOnboardingService(defaults: defaults)
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
        let service = UserDefaultsWorkspaceOnboardingService(defaults: defaults)
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
        let service = UserDefaultsWorkspaceOnboardingService(defaults: defaults)
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
        let service = UserDefaultsWorkspaceOnboardingService(defaults: defaults)
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
}

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

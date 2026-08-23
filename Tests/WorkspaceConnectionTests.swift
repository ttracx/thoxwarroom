import Foundation
import XCTest
import WarRoomCore
import WarRoomOpenWebUI
@testable import ThoxWarRoom

@MainActor
final class WorkspaceConnectionModelTests: XCTestCase {
    func testPublicDiscoveryStopsBeforeProtectedCatalogWithoutCredential() async throws {
        let service = WorkspaceConnectionServiceStub(hasCredential: false)
        let model = WorkspaceConnectionModel(profile: try profile(), service: service)

        model.connect()
        XCTAssertEqual(model.state, .loading)
        await model.waitForCurrentOperation()

        XCTAssertEqual(model.state, .credentialRequired(provenance()))
        let publicRequestCount = await service.publicRequestCount
        let protectedRequestCount = await service.protectedRequestCount
        XCTAssertEqual(publicRequestCount, 1)
        XCTAssertEqual(protectedRequestCount, 0)
    }

    func testCredentialPresentProducesSuccessAndEmptyStates() async throws {
        let models = [OpenWebUIModel(id: "local-model", name: "Local Model")]
        let successService = WorkspaceConnectionServiceStub(
            hasCredential: true,
            models: models
        )
        let successModel = WorkspaceConnectionModel(
            profile: try profile(),
            service: successService
        )

        successModel.connect()
        await successModel.waitForCurrentOperation()
        XCTAssertEqual(successModel.state, .success(provenance(), models))

        let emptyService = WorkspaceConnectionServiceStub(hasCredential: true, models: [])
        let emptyModel = WorkspaceConnectionModel(profile: try profile(), service: emptyService)
        emptyModel.connect()
        await emptyModel.waitForCurrentOperation()
        XCTAssertEqual(emptyModel.state, .empty(provenance()))
    }

    func testOfflineAndContractFailuresUseNonSensitiveStates() async throws {
        let offlineModel = WorkspaceConnectionModel(
            profile: try profile(),
            service: WorkspaceConnectionServiceStub(publicError: .providerOffline)
        )
        offlineModel.connect()
        await offlineModel.waitForCurrentOperation()
        XCTAssertEqual(
            offlineModel.state,
            .offline("The configured provider is unreachable. Check its network and service status.")
        )

        let errorModel = WorkspaceConnectionModel(
            profile: try profile(),
            service: WorkspaceConnectionServiceStub(publicError: .publicDiscoveryUnavailable)
        )
        errorModel.connect()
        await errorModel.waitForCurrentOperation()
        XCTAssertEqual(
            errorModel.state,
            .error("The provider returned an unsupported public discovery response.")
        )
    }

    func testCancelLeavesIdleWithoutSurfacingAnError() async throws {
        let service = WorkspaceConnectionServiceStub(delaysPublicResponse: true)
        let model = WorkspaceConnectionModel(profile: try profile(), service: service)

        model.connect()
        XCTAssertEqual(model.state, .loading)
        model.credentialEntry = "unsubmitted-token"
        model.cancel()
        await model.waitForCurrentOperation()

        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.credentialEntry, "")
    }

    func testSavingCredentialClearsEntryAndThenLoadsProtectedModels() async throws {
        let models = [OpenWebUIModel(id: "local-model")]
        let service = WorkspaceConnectionServiceStub(hasCredential: false, models: models)
        let model = WorkspaceConnectionModel(profile: try profile(), service: service)
        model.credentialEntry = "private-token"

        model.saveCredential()
        await model.waitForCurrentOperation()

        XCTAssertEqual(model.credentialEntry, "")
        XCTAssertNil(model.credentialMessage)
        XCTAssertEqual(model.state, .success(provenance(), models))
        let storeCallCount = await service.storeCallCount
        let storedCredentialByteCount = await service.lastStoredCredentialByteCount
        XCTAssertEqual(storeCallCount, 1)
        XCTAssertEqual(storedCredentialByteCount, 13)
    }

    func testInvalidCredentialIsClearedAndNeverAppearsInErrorState() async throws {
        let model = WorkspaceConnectionModel(
            profile: try profile(),
            service: WorkspaceConnectionServiceStub(storeError: .invalidCredential)
        )
        model.credentialEntry = "private-token"

        model.saveCredential()
        await model.waitForCurrentOperation()

        XCTAssertEqual(model.credentialEntry, "")
        XCTAssertEqual(
            model.credentialMessage,
            "Enter a credential of 16 KiB or less without control characters."
        )
        XCTAssertFalse(model.credentialMessage?.contains("private-token") == true)
    }

    func testConfirmedRemovalDeletesCredentialAndReturnsToCredentialRequired() async throws {
        let service = WorkspaceConnectionServiceStub(
            hasCredential: true,
            models: [OpenWebUIModel(id: "local-model")]
        )
        let model = WorkspaceConnectionModel(profile: try profile(), service: service)
        model.connect()
        await model.waitForCurrentOperation()

        model.removeCredential()
        await model.waitForCurrentOperation()

        let removeCallCount = await service.removeCallCount
        XCTAssertEqual(removeCallCount, 1)
        XCTAssertEqual(model.state, .credentialRequired(provenance()))
    }

    private func profile() throws -> WorkspaceProfile {
        let endpoint = try EndpointValidator.validate(
            "http://127.0.0.1",
            declaredBoundary: .localMachine
        )
        return try WorkspaceProfile(
            id: WorkspaceID(rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!),
            displayName: "Local Lab",
            endpoint: endpoint,
            provider: OpenWebUIProvider.descriptor
        )
    }

    private func provenance() -> WorkspaceConnectionProvenance {
        WorkspaceConnectionProvenance(
            health: .ok,
            deploymentName: "Local Open WebUI",
            version: "0.6.36",
            configurationVersion: "0.6.36",
            authenticationRequired: true
        )
    }
}

final class DefaultWorkspaceConnectionServiceTests: XCTestCase {
    func testPublicDiscoveryNeverReceivesCredentialAndModelsRequireStoredCredential() async throws {
        let workspaceID = WorkspaceID(
            rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        )
        let vault = WorkspaceCredentialVaultStub(
            credentials: [workspaceID: ProviderCredential(bytes: Data("private-token".utf8))]
        )
        let transport = OpenWebUITransportStub()
        let service = DefaultWorkspaceConnectionService(
            credentialVault: vault,
            transport: transport
        )
        let profile = try makeProfile(id: workspaceID)

        let publicResult = try await service.testPublicConnection(for: profile)
        let models = try await service.protectedModels(for: profile)
        let calls = await transport.calls

        XCTAssertEqual(publicResult.health, .ok)
        XCTAssertEqual(publicResult.deploymentName, "Local Open WebUI")
        XCTAssertEqual(models, [OpenWebUIModel(id: "local-model", name: "Local Model")])
        XCTAssertEqual(Set(calls.map(\.path)), ["/health", "/api/version", "/api/config", "/api/models"])
        XCTAssertTrue(calls.filter { $0.path != "/api/models" }.allSatisfy { !$0.hadCredential })
        XCTAssertEqual(calls.first { $0.path == "/api/models" }?.hadCredential, true)
    }

    func testProtectedModelsStopsBeforeTransportWhenCredentialIsAbsent() async throws {
        let vault = WorkspaceCredentialVaultStub(credentials: [:])
        let transport = OpenWebUITransportStub()
        let service = DefaultWorkspaceConnectionService(
            credentialVault: vault,
            transport: transport
        )
        let profile = try makeProfile(id: .make())

        do {
            _ = try await service.protectedModels(for: profile)
            XCTFail("Expected credential gate")
        } catch {
            XCTAssertEqual(error as? WorkspaceConnectionServiceError, .credentialRequired)
        }
        let transportCalls = await transport.calls
        XCTAssertTrue(transportCalls.isEmpty)
    }

    func testCredentialValidationRejectsControlCharactersBeforeKeychain() async throws {
        let vault = WorkspaceCredentialVaultStub(credentials: [:])
        let service = DefaultWorkspaceConnectionService(
            credentialVault: vault,
            transport: OpenWebUITransportStub()
        )
        let workspaceID = WorkspaceID.make()

        for value in [
            "",
            "token\nsecond-line",
            "token\u{7F}",
            String(repeating: "a", count: 16 * 1_024 + 1),
        ] {
            do {
                try await service.storeCredential(value, for: workspaceID)
                XCTFail("Expected credential validation")
            } catch {
                XCTAssertEqual(error as? WorkspaceConnectionServiceError, .invalidCredential)
            }
        }
        let storeCallCount = await vault.storeCallCount
        XCTAssertEqual(storeCallCount, 0)
    }

    private func makeProfile(id: WorkspaceID) throws -> WorkspaceProfile {
        let endpoint = try EndpointValidator.validate(
            "http://127.0.0.1",
            declaredBoundary: .localMachine
        )
        return try WorkspaceProfile(
            id: id,
            displayName: "Local Lab",
            endpoint: endpoint,
            provider: OpenWebUIProvider.descriptor
        )
    }
}

private actor WorkspaceConnectionServiceStub: WorkspaceConnectionServicing {
    private var credentialPresent: Bool
    private let models: [OpenWebUIModel]
    private let publicError: WorkspaceConnectionServiceError?
    private let storeError: WorkspaceConnectionServiceError?
    private let delaysPublicResponse: Bool

    private(set) var publicRequestCount = 0
    private(set) var protectedRequestCount = 0
    private(set) var storeCallCount = 0
    private(set) var removeCallCount = 0
    private(set) var lastStoredCredentialByteCount: Int?

    init(
        hasCredential: Bool = false,
        models: [OpenWebUIModel] = [],
        publicError: WorkspaceConnectionServiceError? = nil,
        storeError: WorkspaceConnectionServiceError? = nil,
        delaysPublicResponse: Bool = false
    ) {
        self.credentialPresent = hasCredential
        self.models = models
        self.publicError = publicError
        self.storeError = storeError
        self.delaysPublicResponse = delaysPublicResponse
    }

    func hasCredential(for workspaceID: WorkspaceID) -> Bool {
        credentialPresent
    }

    func storeCredential(_ value: String, for workspaceID: WorkspaceID) throws {
        storeCallCount += 1
        lastStoredCredentialByteCount = value.utf8.count
        if let storeError { throw storeError }
        credentialPresent = true
    }

    func removeCredential(for workspaceID: WorkspaceID) {
        removeCallCount += 1
        credentialPresent = false
    }

    func testPublicConnection(
        for profile: WorkspaceProfile
    ) async throws -> WorkspaceConnectionProvenance {
        publicRequestCount += 1
        if delaysPublicResponse {
            try await Task.sleep(nanoseconds: 30_000_000_000)
        }
        if let publicError { throw publicError }
        return WorkspaceConnectionProvenance(
            health: .ok,
            deploymentName: "Local Open WebUI",
            version: "0.6.36",
            configurationVersion: "0.6.36",
            authenticationRequired: true
        )
    }

    func protectedModels(for profile: WorkspaceProfile) -> [OpenWebUIModel] {
        protectedRequestCount += 1
        return models
    }
}

private actor WorkspaceCredentialVaultStub: CredentialVault {
    private var credentials: [WorkspaceID: ProviderCredential]
    private(set) var storeCallCount = 0

    init(credentials: [WorkspaceID: ProviderCredential]) {
        self.credentials = credentials
    }

    func credential(for workspaceID: WorkspaceID) -> ProviderCredential? {
        credentials[workspaceID]
    }

    func store(_ credential: ProviderCredential, for workspaceID: WorkspaceID) {
        storeCallCount += 1
        credentials[workspaceID] = credential
    }

    func deleteCredential(for workspaceID: WorkspaceID) {
        credentials[workspaceID] = nil
    }
}

private actor OpenWebUITransportStub: ProviderTransport {
    struct Call: Sendable {
        let path: String
        let hadCredential: Bool
    }

    private(set) var calls: [Call] = []

    func send(
        _ request: ProviderRequest,
        to endpoint: ValidatedEndpoint,
        credential: ProviderCredential?
    ) throws -> ProviderResponse {
        calls.append(Call(path: request.relativePath, hadCredential: credential != nil))
        switch request.relativePath {
        case "/health":
            return ProviderResponse(statusCode: 200, body: Data("OK".utf8))
        case "/api/version":
            return ProviderResponse(
                statusCode: 200,
                body: Data(#"{"version":"0.6.36"}"#.utf8)
            )
        case "/api/config":
            return ProviderResponse(
                statusCode: 200,
                body: Data(#"{"status":true,"name":"Local Open WebUI","version":"0.6.36","default_locale":"en-US","features":{"auth":true,"auth_trusted_header":false,"enable_signup_password_confirmation":false,"enable_ldap":false,"enable_signup":false,"enable_login_form":true,"enable_websocket":true}}"#.utf8)
            )
        case "/api/models":
            return ProviderResponse(
                statusCode: 200,
                body: Data(#"{"data":[{"id":"local-model","name":"Local Model"}]}"#.utf8)
            )
        default:
            return ProviderResponse(statusCode: 404, body: Data())
        }
    }
}

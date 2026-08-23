import Foundation
import WarRoomAppleInfrastructure
import WarRoomCore
import WarRoomOpenWebUI

protocol WorkspaceConnectionServicing: Sendable {
    func hasCredential(for workspaceID: WorkspaceID) async throws -> Bool
    func storeCredential(_ value: String, for workspaceID: WorkspaceID) async throws
    func removeCredential(for workspaceID: WorkspaceID) async throws
    func testPublicConnection(
        for profile: WorkspaceProfile
    ) async throws -> WorkspaceConnectionProvenance
    func protectedModels(for profile: WorkspaceProfile) async throws -> [OpenWebUIModel]
}

struct DefaultWorkspaceConnectionService: WorkspaceConnectionServicing, Sendable {
    private static let maximumCredentialBytes = 16 * 1_024

    private let credentialVault: any CredentialVault
    private let transport: any ProviderTransport

    init(
        credentialVault: any CredentialVault = KeychainCredentialVault(),
        transport: any ProviderTransport = URLSessionProviderTransport()
    ) {
        self.credentialVault = credentialVault
        self.transport = transport
    }

    func hasCredential(for workspaceID: WorkspaceID) async throws -> Bool {
        do {
            return try await credentialVault.credential(for: workspaceID) != nil
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WorkspaceConnectionServiceError.credentialStoreUnavailable
        }
    }

    func storeCredential(_ value: String, for workspaceID: WorkspaceID) async throws {
        guard !value.isEmpty,
              value.utf8.count <= Self.maximumCredentialBytes else {
            throw WorkspaceConnectionServiceError.invalidCredential
        }
        let bytes = Data(value.utf8)
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 != 0x7F }) else {
            throw WorkspaceConnectionServiceError.invalidCredential
        }
        do {
            try await credentialVault.store(
                ProviderCredential(bytes: bytes),
                for: workspaceID
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as WorkspaceConnectionServiceError {
            throw error
        } catch {
            throw WorkspaceConnectionServiceError.credentialStoreUnavailable
        }
    }

    func removeCredential(for workspaceID: WorkspaceID) async throws {
        do {
            try await credentialVault.deleteCredential(for: workspaceID)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WorkspaceConnectionServiceError.credentialStoreUnavailable
        }
    }

    func testPublicConnection(
        for profile: WorkspaceProfile
    ) async throws -> WorkspaceConnectionProvenance {
        let client = OpenWebUIClient(
            endpoint: profile.endpoint,
            transport: transport,
            descriptor: OpenWebUIProvider.descriptor
        )
        do {
            try Task.checkCancellation()
            async let health = client.health()
            async let version = client.version()
            async let configuration = client.configuration()
            let values = try await (health, version, configuration)
            try Task.checkCancellation()
            return WorkspaceConnectionProvenance(
                health: values.0.status,
                deploymentName: values.2.name,
                version: values.1.version,
                configurationVersion: values.2.version,
                authenticationRequired: values.2.features.auth
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as OpenWebUIProviderError {
            if case .transportFailure = error {
                throw WorkspaceConnectionServiceError.providerOffline
            }
            throw WorkspaceConnectionServiceError.publicDiscoveryUnavailable
        } catch {
            throw WorkspaceConnectionServiceError.publicDiscoveryUnavailable
        }
    }

    func protectedModels(for profile: WorkspaceProfile) async throws -> [OpenWebUIModel] {
        let credential: ProviderCredential
        do {
            guard let storedCredential = try await credentialVault.credential(for: profile.id) else {
                throw WorkspaceConnectionServiceError.credentialRequired
            }
            credential = storedCredential
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as WorkspaceConnectionServiceError {
            throw error
        } catch {
            throw WorkspaceConnectionServiceError.credentialStoreUnavailable
        }

        let client = OpenWebUIClient(
            endpoint: profile.endpoint,
            transport: transport,
            credential: credential,
            descriptor: OpenWebUIProvider.descriptor
        )
        do {
            try Task.checkCancellation()
            let catalog = try await client.models()
            try Task.checkCancellation()
            return catalog.data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as OpenWebUIProviderError {
            if case .transportFailure = error {
                throw WorkspaceConnectionServiceError.providerOffline
            }
            throw WorkspaceConnectionServiceError.modelCatalogUnavailable
        } catch {
            throw WorkspaceConnectionServiceError.modelCatalogUnavailable
        }
    }
}

import Foundation
import WarRoomCore

@MainActor
protocol WorkspaceOnboardingServicing {
    func loadConfiguration() async throws -> WorkspaceProfile?
    func saveConfiguration(from draft: WorkspaceDraft) async throws -> WorkspaceProfile
    func deleteConfiguration() async throws
}

enum WorkspaceOnboardingError: LocalizedError {
    case validation(String)
    case persistence

    var errorDescription: String? {
        switch self {
        case .validation(let message): message
        case .persistence: "Workspace configuration is unavailable on this device."
        }
    }
}

/// Stores endpoint/profile metadata only. Credentials are deliberately excluded
/// and will flow through WarRoomCore.CredentialVault once authentication lands.
@MainActor
final class UserDefaultsWorkspaceOnboardingService: WorkspaceOnboardingServicing {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, key: String = "workspace.profile.v1") {
        self.defaults = defaults
        self.key = key
    }

    func loadConfiguration() async throws -> WorkspaceProfile? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do { return try decoder.decode(WorkspaceProfile.self, from: data) }
        catch { throw WorkspaceOnboardingError.persistence }
    }

    func saveConfiguration(from draft: WorkspaceDraft) async throws -> WorkspaceProfile {
        do {
            let endpoint = try EndpointValidator.validate(
                draft.endpoint,
                declaredBoundary: draft.boundary,
                hostedAccess: draft.hasHostedDataTransferConsent ? .granted : .denied
            )
            let profile = try WorkspaceProfile(
                displayName: draft.name,
                endpoint: endpoint,
                provider: ProviderDescriptor(
                    id: ProviderID(rawValue: "workspace-provider"),
                    displayName: "Workspace provider",
                    capabilities: []
                )
            )
            defaults.set(try encoder.encode(profile), forKey: key)
            guard defaults.data(forKey: key) != nil else { throw WorkspaceOnboardingError.persistence }
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
        defaults.removeObject(forKey: key)
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

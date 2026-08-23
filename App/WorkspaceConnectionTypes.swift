import Foundation
import WarRoomCore
import WarRoomOpenWebUI

struct WorkspaceConnectionProvenance: Equatable, Sendable {
    let health: OpenWebUIHealth.Status
    let deploymentName: String
    let version: String
    let configurationVersion: String
    let authenticationRequired: Bool
}

enum WorkspaceConnectionServiceError: Error, Equatable, Sendable {
    case credentialRequired
    case invalidCredential
    case credentialStoreUnavailable
    case providerOffline
    case publicDiscoveryUnavailable
    case modelCatalogUnavailable
}

extension WorkspaceConnectionServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .credentialRequired:
            "Add a provider credential before loading protected models."
        case .invalidCredential:
            "Enter a credential of 16 KiB or less without control characters."
        case .credentialStoreUnavailable:
            "Secure credential storage is unavailable on this device."
        case .providerOffline:
            "The configured provider is unreachable. Check its network and service status."
        case .publicDiscoveryUnavailable:
            "The provider returned an unsupported public discovery response."
        case .modelCatalogUnavailable:
            "The protected model catalog is unavailable for this credential."
        }
    }
}

extension NetworkBoundary {
    var connectionProvenance: String {
        switch self {
        case .localMachine:
            "Requests remain on this device and use the configured loopback endpoint."
        case .privateNetwork:
            "Requests go only to the configured private-network endpoint."
        case .hosted:
            "Requests go to the explicitly authorized hosted endpoint and may leave this device."
        }
    }
}

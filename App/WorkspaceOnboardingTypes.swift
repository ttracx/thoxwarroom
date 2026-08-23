import Foundation
import WarRoomCore
import WarRoomHermes
import WarRoomMesh
import WarRoomOpenWebUI

enum WorkspaceProviderKind: String, CaseIterable, Equatable, Sendable {
    case openWebUI
    case hermes
    case meshStack

    var title: String {
        switch self {
        case .openWebUI: "Open WebUI"
        case .hermes: "Hermes Agent"
        case .meshStack: "MeshStack War Room"
        }
    }

    var detail: String {
        switch self {
        case .openWebUI: "Discover health, configuration, and protected models."
        case .hermes: "Review run status and buffered events without mutating controls."
        case .meshStack: "Review fleet, topology, and event status without control-plane actions."
        }
    }

    var descriptor: ProviderDescriptor {
        switch self {
        case .openWebUI: OpenWebUIProvider.descriptor
        case .hermes: HermesProvider.descriptor
        case .meshStack: MeshProvider.descriptor
        }
    }

    var endpointPolicy: EndpointValidationPolicy {
        switch self {
        case .openWebUI:
            EndpointValidationPolicy(
                allowedHTTPPorts: [80, 3_000, 8_080],
                allowedHTTPSPorts: [443, 8_443]
            )
        case .hermes:
            EndpointValidationPolicy(
                allowedHTTPPorts: [80, 8_000, 8_080, 8_642],
                allowedHTTPSPorts: [443, 8_443]
            )
        case .meshStack:
            .secureDefault
        }
    }

    init?(providerID: ProviderID) {
        switch providerID.rawValue {
        case OpenWebUIProvider.descriptor.id.rawValue, "workspace-provider": self = .openWebUI
        case HermesProvider.descriptor.id.rawValue: self = .hermes
        case MeshProvider.descriptor.id.rawValue: self = .meshStack
        default: return nil
        }
    }
}

enum WorkspaceNativeFeatureRoute: Equatable, Sendable {
    case openWebUIConnection
    case hermesReview
    case warRoomDashboard

    init?(profile: WorkspaceProfile) {
        guard let providerKind = WorkspaceProviderKind(providerID: profile.provider.id) else {
            return nil
        }
        switch providerKind {
        case .openWebUI:
            let isLegacyProfile = profile.provider.id.rawValue == "workspace-provider"
            guard isLegacyProfile || profile.provider.supports(.modelCatalog) else { return nil }
            self = .openWebUIConnection
        case .hermes:
            guard profile.provider.supports(.hermesSessions) else { return nil }
            self = .hermesReview
        case .meshStack:
            guard profile.provider.supports(.warRoomStatus) else { return nil }
            self = .warRoomDashboard
        }
    }

    var buttonTitle: String {
        switch self {
        case .openWebUIConnection: "Open provider connection"
        case .hermesReview: "Open run review"
        case .warRoomDashboard: "Open War Room dashboard"
        }
    }
}

struct WorkspaceDraft: Equatable, Sendable {
    var name = ""
    var endpoint = ""
    var providerKind: WorkspaceProviderKind = .openWebUI
    var boundary: NetworkBoundary = .localMachine
    var hasHostedDataTransferConsent = false
}

extension NetworkBoundary {
    var title: String {
        switch self {
        case .localMachine: "Local device"
        case .privateNetwork: "Private network"
        case .hosted: "Hosted service"
        }
    }

    var systemImage: String {
        switch self {
        case .localMachine: "desktopcomputer"
        case .privateNetwork: "lock.shield"
        case .hosted: "cloud"
        }
    }

    var privacySummary: String {
        switch self {
        case .localMachine: "Traffic stays on this device. No hosted service is contacted."
        case .privateNetwork: "Traffic goes only to infrastructure controlled by your organization."
        case .hosted: "Prompts and workspace data may leave this device for the configured host."
        }
    }
}

extension WorkspaceProfile {
    /// Kept off until THOX has verified the hosted service's retention,
    /// embedded-resource domains, and App Store privacy declarations.
    static let isHostedCompatibilityEnabled = false

    /// The legacy WKWebView has its own exact-origin policy and may only be
    /// entered after this independently validated hosted profile is selected.
    var supportsHostedCompatibilityOrigin: Bool {
        Self.isHostedCompatibilityEnabled &&
            WorkspaceProviderKind(providerID: provider.id) == .openWebUI &&
            endpoint.boundary == .hosted &&
            endpoint.url.scheme?.lowercased() == "https" &&
            endpoint.url.host?.lowercased() == "webui.thox.ai" &&
            endpoint.url.port == nil &&
            endpoint.url.path.isEmpty
    }
}

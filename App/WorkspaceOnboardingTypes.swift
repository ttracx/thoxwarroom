import Foundation
import WarRoomCore

struct WorkspaceDraft: Equatable, Sendable {
    var name = ""
    var endpoint = ""
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
    /// The legacy WKWebView has its own exact-origin policy and may only be
    /// entered after this independently validated hosted profile is selected.
    var supportsHostedCompatibilityOrigin: Bool {
        endpoint.boundary == .hosted &&
            endpoint.url.scheme?.lowercased() == "https" &&
            endpoint.url.host?.lowercased() == "webui.thox.ai" &&
            endpoint.url.port == nil &&
            endpoint.url.path.isEmpty
    }
}

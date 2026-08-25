import SwiftUI
import WarRoomCore

struct ContentView: View {
    private enum Destination {
        case hostedCompatibility
        case providerConnection(WorkspaceProfile)
        case hermesReview(WorkspaceProfile)
        case warRoomDashboard(WorkspaceProfile)
        case workspaceBrowser(WorkspaceProfile)
        case auditCenter(WorkspaceProfile)
        case chatPreview(WorkspaceProfile)
    }

    #if os(macOS)
    private enum MacDestination: String, Hashable {
        case workspace
        case nativeFeature
        case workspaceBrowser
        case auditCenter
        case hostedCompatibility
        case chatPreview
    }
    #endif

    @EnvironmentObject private var webViewModel: ThoxWebViewModel
    @StateObject private var onboardingModel: WorkspaceOnboardingModel
    @State private var destination: Destination?
    #if os(macOS)
    @State private var macDestination: MacDestination = .workspace
    #endif

    @MainActor
    init() {
        let service = EncryptedWorkspaceOnboardingService()
        _onboardingModel = StateObject(wrappedValue: WorkspaceOnboardingModel(service: service))
    }

    @MainActor
    init(service: any WorkspaceOnboardingServicing) {
        _onboardingModel = StateObject(wrappedValue: WorkspaceOnboardingModel(service: service))
    }

    var body: some View {
        #if os(macOS)
        macOSContent
        #else
        iOSContent
        #endif
    }

    #if os(macOS)
    private var macOSContent: some View {
        NavigationSplitView {
            List(selection: $macDestination) {
                Label("Workspace", systemImage: "square.grid.2x2")
                    .tag(MacDestination.workspace)
                    .accessibilityIdentifier("mac-sidebar-workspace")
                if let profile = configuredProfile {
                    Section("Chat surface") {
                        Label("Chat preview", systemImage: "bubble.left.and.text.bubble.right")
                            .tag(MacDestination.chatPreview)
                            .accessibilityIdentifier("mac-sidebar-chat-preview")
                    }
                    Section("Read-only tools") {
                        if let route = WorkspaceNativeFeatureRoute(profile: profile) {
                            Label(sidebarTitle(for: route), systemImage: sidebarIcon(for: route))
                                .tag(MacDestination.nativeFeature)
                                .accessibilityIdentifier("mac-sidebar-native-feature")
                        }
                        if profile.supportsLocalWorkspaceBrowser {
                            Label("Local files", systemImage: "folder")
                                .tag(MacDestination.workspaceBrowser)
                                .accessibilityIdentifier("mac-sidebar-workspace-browser")
                        }
                        if profile.supportsHostedCompatibilityOrigin {
                            Label("Hosted compatibility", systemImage: "globe")
                                .tag(MacDestination.hostedCompatibility)
                                .accessibilityIdentifier("mac-sidebar-hosted")
                        }
                    }
                    Section("Workspace controls") {
                        Label("Audit policy & export", systemImage: "checkmark.shield")
                            .tag(MacDestination.auditCenter)
                            .accessibilityIdentifier("mac-sidebar-audit-center")
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle(configuredProfile?.displayName ?? "THOX War Room")
            .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 300)
            .accessibilityIdentifier("mac-workspace-sidebar")
        } detail: {
            macOSDetail
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: onboardingModel.phase) { _, _ in
            Task { @MainActor in
                await Task.yield()
                reconcileMacDestination()
            }
        }
    }

    @ViewBuilder
    private var macOSDetail: some View {
        switch macDestination {
        case .workspace:
            workspaceOverview(
                onOpenNativeFeature: { _ in macDestination = .nativeFeature },
                onOpenHostedCompatibility: { _ in macDestination = .hostedCompatibility },
                onOpenWorkspaceBrowser: { _ in macDestination = .workspaceBrowser },
                onOpenAuditCenter: { _ in macDestination = .auditCenter },
                onOpenChatPreview: { _ in macDestination = .chatPreview }
            )
        case .nativeFeature:
            if let profile = configuredProfile {
                nativeFeature(profile: profile) { macDestination = .workspace }
            } else {
                unavailableMacDestination
            }
        case .workspaceBrowser:
            if let profile = configuredProfile, profile.supportsLocalWorkspaceBrowser {
                WorkspaceBrowserHost(profile: profile) { macDestination = .workspace }
            } else {
                unavailableMacDestination
            }
        case .auditCenter:
            if let profile = configuredProfile {
                WorkspaceAuditCenterHost(profile: profile) { macDestination = .workspace }
            } else {
                unavailableMacDestination
            }
        case .hostedCompatibility:
            if configuredProfile?.supportsHostedCompatibilityOrigin == true {
                HostedCompatibilityView(model: webViewModel) { macDestination = .workspace }
            } else {
                unavailableMacDestination
            }
        case .chatPreview:
            if let profile = configuredProfile {
                WarRoomChatPreviewHost(profile: profile) { macDestination = .workspace }
            } else {
                unavailableMacDestination
            }
        }
    }

    private var unavailableMacDestination: some View {
        VStack(spacing: 12) {
            Label("Feature unavailable", systemImage: "exclamationmark.triangle")
                .font(.title2.weight(.semibold))
            Text("Return to Workspace and choose a feature supported by the current configuration.")
                .foregroundStyle(.secondary)
            Button("Return to Workspace") { macDestination = .workspace }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .workspaceReturnCommand(WorkspaceCommandAction("Return to Workspace") {
            macDestination = .workspace
        })
    }

    private var configuredProfile: WorkspaceProfile? {
        guard case .ready(let profile) = onboardingModel.phase else { return nil }
        return profile
    }

    private func reconcileMacDestination() {
        guard let profile = configuredProfile else {
            if macDestination != .workspace {
                macDestination = .workspace
            }
            return
        }
        switch macDestination {
        case .workspace:
            break
        case .nativeFeature:
            if WorkspaceNativeFeatureRoute(profile: profile) == nil {
                macDestination = .workspace
            }
        case .workspaceBrowser:
            if !profile.supportsLocalWorkspaceBrowser {
                macDestination = .workspace
            }
        case .auditCenter:
            break
        case .hostedCompatibility:
            if !profile.supportsHostedCompatibilityOrigin {
                macDestination = .workspace
            }
        case .chatPreview:
            break
        }
    }

    private func sidebarTitle(for route: WorkspaceNativeFeatureRoute) -> String {
        switch route {
        case .openWebUIConnection: "Provider connection"
        case .hermesReview: "Hermes review"
        case .warRoomDashboard: "War Room dashboard"
        }
    }

    private func sidebarIcon(for route: WorkspaceNativeFeatureRoute) -> String {
        switch route {
        case .openWebUIConnection: "network"
        case .hermesReview: "eye"
        case .warRoomDashboard: "point.3.connected.trianglepath.dotted"
        }
    }
    #endif

    @ViewBuilder
    private var iOSContent: some View {
        switch destination {
        case .hostedCompatibility:
            HostedCompatibilityView(model: webViewModel) { destination = nil }
        case .providerConnection(let profile):
            WorkspaceConnectionHost(profile: profile) { destination = nil }
        case .hermesReview(let profile):
            HermesRunReviewHost(profile: profile) { destination = nil }
        case .warRoomDashboard(let profile):
            WarRoomDashboardHost(profile: profile) { destination = nil }
        case .workspaceBrowser(let profile):
            WorkspaceBrowserHost(profile: profile) { destination = nil }
        case .auditCenter(let profile):
            WorkspaceAuditCenterHost(profile: profile) { destination = nil }
        case .chatPreview(let profile):
            WarRoomChatPreviewHost(profile: profile) { destination = nil }
        case nil:
            workspaceOverview(
                onOpenNativeFeature: { profile in
                    destination = destination(for: profile)
                },
                onOpenHostedCompatibility: { _ in destination = .hostedCompatibility },
                onOpenWorkspaceBrowser: { profile in destination = .workspaceBrowser(profile) },
                onOpenAuditCenter: { profile in destination = .auditCenter(profile) },
                onOpenChatPreview: { profile in destination = .chatPreview(profile) }
            )
        }
    }

    private func workspaceOverview(
        onOpenNativeFeature: @escaping (WorkspaceProfile) -> Void,
        onOpenHostedCompatibility: @escaping (WorkspaceProfile) -> Void,
        onOpenWorkspaceBrowser: @escaping (WorkspaceProfile) -> Void,
        onOpenAuditCenter: @escaping (WorkspaceProfile) -> Void,
        onOpenChatPreview: @escaping (WorkspaceProfile) -> Void
    ) -> some View {
        WorkspaceOnboardingView(
            model: onboardingModel,
            onOpenNativeFeature: onOpenNativeFeature,
            onOpenHostedCompatibility: onOpenHostedCompatibility,
            onOpenWorkspaceBrowser: onOpenWorkspaceBrowser,
            onOpenAuditCenter: onOpenAuditCenter,
            onOpenChatPreview: onOpenChatPreview
        )
    }

    @ViewBuilder
    private func nativeFeature(profile: WorkspaceProfile, onClose: @escaping () -> Void) -> some View {
        switch WorkspaceNativeFeatureRoute(profile: profile) {
        case .openWebUIConnection:
            WorkspaceConnectionHost(profile: profile, onClose: onClose)
        case .hermesReview:
            HermesRunReviewHost(profile: profile, onClose: onClose)
        case .warRoomDashboard:
            WarRoomDashboardHost(profile: profile, onClose: onClose)
        case nil:
            EmptyView()
        }
    }

    private func destination(for profile: WorkspaceProfile) -> Destination? {
        switch WorkspaceNativeFeatureRoute(profile: profile) {
        case .openWebUIConnection: .providerConnection(profile)
        case .hermesReview: .hermesReview(profile)
        case .warRoomDashboard: .warRoomDashboard(profile)
        case nil: nil
        }
    }
}

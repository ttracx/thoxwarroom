import SwiftUI
import WarRoomCore

struct ContentView: View {
    private enum Destination {
        case hostedCompatibility
        case providerConnection(WorkspaceProfile)
        case hermesReview(WorkspaceProfile)
    }

    @EnvironmentObject private var webViewModel: ThoxWebViewModel
    @StateObject private var onboardingModel: WorkspaceOnboardingModel
    @State private var destination: Destination?

    @MainActor
    init() {
        let service = UserDefaultsWorkspaceOnboardingService()
        _onboardingModel = StateObject(wrappedValue: WorkspaceOnboardingModel(service: service))
    }

    @MainActor
    init(service: any WorkspaceOnboardingServicing) {
        _onboardingModel = StateObject(wrappedValue: WorkspaceOnboardingModel(service: service))
    }

    var body: some View {
        switch destination {
        case .hostedCompatibility:
            HostedCompatibilityView(model: webViewModel) {
                destination = nil
            }
        case .providerConnection(let profile):
            WorkspaceConnectionHost(profile: profile) { destination = nil }
        case .hermesReview(let profile):
            HermesRunReviewHost(profile: profile) { destination = nil }
        case nil:
            WorkspaceOnboardingView(
                model: onboardingModel,
                onOpenNativeFeature: { profile in
                    switch WorkspaceProviderKind(providerID: profile.provider.id) {
                    case .openWebUI: destination = .providerConnection(profile)
                    case .hermes: destination = .hermesReview(profile)
                    case nil: break
                    }
                },
                onOpenHostedCompatibility: { _ in
                    destination = .hostedCompatibility
                }
            )
        }
    }
}

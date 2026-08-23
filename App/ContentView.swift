import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var webViewModel: ThoxWebViewModel
    @StateObject private var onboardingModel: WorkspaceOnboardingModel
    @State private var isHostedCompatibilityPresented = false

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
        if isHostedCompatibilityPresented {
            HostedCompatibilityView(model: webViewModel) {
                isHostedCompatibilityPresented = false
            }
        } else {
            WorkspaceOnboardingView(model: onboardingModel) { _ in
                isHostedCompatibilityPresented = true
            }
        }
    }
}

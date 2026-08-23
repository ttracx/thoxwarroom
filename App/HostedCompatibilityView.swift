import SwiftUI

/// Explicitly entered compatibility surface for the one hosted origin supported
/// by the legacy web model. Onboarding must authorize this boundary first.
struct HostedCompatibilityView: View {
    @ObservedObject var model: ThoxWebViewModel
    let onShowWorkspace: () -> Void
    @State private var isClearConfirmationPresented = false

    var body: some View {
        ZStack {
            ThoxTheme.background.ignoresSafeArea()
            ThoxWebView(model: model)
                .opacity(model.state == .loaded ? 1 : 0)
            switch model.state {
            case .idle, .loading:
                LoadingOverlay(kind: .loading, onRetry: { model.reload() })
            case .error(let message):
                LoadingOverlay(kind: .error(message), onRetry: { model.resetForRetry() })
            case .loaded:
                EmptyView()
            }
            VStack {
                HStack {
                    Button(action: onShowWorkspace) {
                        Label("Workspace", systemImage: "chevron.backward")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("show-workspace")
                    Spacer()
                    sessionControls
                }
                Spacer()
            }
            .padding()
        }
        .animation(.easeInOut(duration: 0.18), value: model.state)
        .confirmationDialog(
            "Sign out and clear this session?",
            isPresented: $isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Sign Out & Clear Session", role: .destructive) {
                Task { await model.clearPersistentSession() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cookies, local storage, caches, and other website data saved by ThoxWarRoom will be removed from this device.")
        }
    }

    @ViewBuilder
    private var sessionControls: some View {
        switch model.sessionClearState {
        case .clearing:
            Label("Clearing session…", systemImage: "hourglass")
                .accessibilityLabel("Clearing persistent session")
        case .cleared:
            Label("Session cleared", systemImage: "checkmark.shield")
        case .failed(let message):
            VStack(alignment: .trailing, spacing: 6) {
                Text(message).font(.caption).foregroundStyle(.red)
                clearSessionButton
            }
        case .persistent:
            clearSessionButton
        }
    }

    private var clearSessionButton: some View {
        Button { isClearConfirmationPresented = true } label: {
            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Clears cookies and all persistent website data after confirmation")
    }
}

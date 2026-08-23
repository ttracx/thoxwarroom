import SwiftUI
import WarRoomAppleInfrastructure
import WarRoomCore
import WarRoomHermes

struct WorkspaceConnectionHost: View {
    @StateObject private var model: WorkspaceConnectionModel
    let onClose: () -> Void

    init(profile: WorkspaceProfile, onClose: @escaping () -> Void) {
        _model = StateObject(wrappedValue: WorkspaceConnectionModel(
            profile: profile,
            service: DefaultWorkspaceConnectionService()
        ))
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            WorkspaceConnectionView(model: model)
                .toolbar { closeButton }
        }
    }

    @ToolbarContentBuilder
    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Workspace", action: onClose)
        }
    }
}

struct HermesRunReviewHost: View {
    @StateObject private var accessModel: HermesCredentialAccessModel
    @StateObject private var reviewModel: HermesRunReviewModel
    let onClose: () -> Void
    @State private var isCredentialRemovalPresented = false

    init(profile: WorkspaceProfile, onClose: @escaping () -> Void) {
        let vault = KeychainCredentialVault()
        let credentialService = DefaultWorkspaceConnectionService(credentialVault: vault)
        _accessModel = StateObject(wrappedValue: HermesCredentialAccessModel(
            profile: profile,
            service: credentialService
        ))
        _reviewModel = StateObject(wrappedValue: HermesRunReviewModel(
            service: WorkspaceHermesRunReviewService(
                profile: profile,
                vault: vault
            )
        ))
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Hermes review")
                .toolbar {
                    closeButton
                    if accessModel.phase == .ready {
                        ToolbarItem(placement: .destructiveAction) {
                            Button("Remove credential", role: .destructive) {
                                isCredentialRemovalPresented = true
                            }
                        }
                    }
                }
        }
        .task(id: accessModel.profile.id) { await accessModel.refresh() }
        .onDisappear { reviewModel.cancelLoading() }
        .confirmationDialog(
            "Remove this Hermes credential?",
            isPresented: $isCredentialRemovalPresented,
            titleVisibility: .visible
        ) {
            Button("Remove Credential", role: .destructive) {
                Task { await accessModel.removeCredential() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the workspace credential from this device's Keychain. It does not contact Hermes or delete server-side data.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch accessModel.phase {
        case .loading:
            ProgressView("Checking secure credential storage…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("hermes-credential-loading")
        case .credentialRequired:
            VStack(alignment: .leading, spacing: 16) {
                Label(accessModel.profile.displayName, systemImage: "key.fill")
                    .font(.title2.weight(.semibold))
                Text("Add the Hermes bearer token for this workspace. It is stored only in this device's non-synchronizing Keychain and is never written to workspace metadata.")
                    .foregroundStyle(.secondary)
                SecureField("Hermes bearer token", text: $accessModel.credentialEntry)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .privacySensitive()
                    .accessibilityIdentifier("hermes-credential")
                if let message = accessModel.message {
                    Label(message, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                }
                Button("Save credential", action: accessModel.saveCredential)
                    .buttonStyle(.borderedProminent)
                    .disabled(accessModel.credentialEntry.isEmpty)
                    .accessibilityIdentifier("save-hermes-credential")
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(24)
        case .ready:
            HermesRunReviewView(model: reviewModel)
        case .failed(let message):
            VStack(spacing: 16) {
                Label("Secure storage unavailable", systemImage: "exclamationmark.triangle.fill")
                    .font(.title2.weight(.semibold))
                Text(message).foregroundStyle(.secondary)
                Button("Try again") { Task { await accessModel.refresh() } }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
    }

    @ToolbarContentBuilder
    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Workspace", action: onClose)
        }
    }
}

@MainActor
private final class HermesCredentialAccessModel: ObservableObject {
    enum Phase: Equatable { case loading, credentialRequired, ready, failed(String) }

    @Published private(set) var phase: Phase = .loading
    @Published var credentialEntry = ""
    @Published private(set) var message: String?

    let profile: WorkspaceProfile
    private let service: any WorkspaceConnectionServicing

    init(profile: WorkspaceProfile, service: any WorkspaceConnectionServicing) {
        self.profile = profile
        self.service = service
    }

    func refresh() async {
        phase = .loading
        message = nil
        do {
            phase = try await service.hasCredential(for: profile.id) ? .ready : .credentialRequired
        } catch is CancellationError {
            return
        } catch {
            phase = .failed("Secure credential storage is unavailable on this device.")
        }
    }

    func saveCredential() {
        let submitted = credentialEntry
        credentialEntry = ""
        message = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                try await service.storeCredential(submitted, for: profile.id)
                phase = .ready
            } catch is CancellationError {
                return
            } catch {
                message = error as? WorkspaceConnectionServiceError == .invalidCredential
                    ? WorkspaceConnectionServiceError.invalidCredential.localizedDescription
                    : "Secure credential storage is unavailable on this device."
                phase = .credentialRequired
            }
        }
    }

    func removeCredential() async {
        reviewReset()
        do {
            try await service.removeCredential(for: profile.id)
            phase = .credentialRequired
        } catch is CancellationError {
            return
        } catch {
            phase = .failed("Secure credential storage is unavailable on this device.")
        }
    }

    private func reviewReset() {
        credentialEntry = ""
        message = nil
        phase = .loading
    }
}

private actor WorkspaceHermesRunReviewService: HermesRunReviewServicing {
    let profile: WorkspaceProfile
    let vault: any CredentialVault
    let transport: any ProviderTransport

    init(
        profile: WorkspaceProfile,
        vault: any CredentialVault = KeychainCredentialVault(),
        transport: any ProviderTransport = URLSessionProviderTransport()
    ) {
        self.profile = profile
        self.vault = vault
        self.transport = transport
    }

    func loadSnapshot(for runID: HermesRunID) async throws -> HermesRunReviewSnapshot {
        guard profile.provider.id == HermesProvider.descriptor.id,
              profile.provider.supports(.hermesSessions) else {
            throw WorkspaceConnectionServiceError.publicDiscoveryUnavailable
        }
        guard let credential = try await vault.credential(for: profile.id) else {
            throw WorkspaceConnectionServiceError.credentialRequired
        }
        let client = HermesAPIClient(
            transport: transport,
            endpoint: profile.endpoint,
            credential: credential
        )
        return try await HermesAPIReadOnlyReviewService(client: client).loadSnapshot(for: runID)
    }
}

import SwiftUI
import WarRoomAppleInfrastructure
import WarRoomCore
import WarRoomMesh

struct WarRoomDashboardRouteSelection: Equatable, Sendable {
    let meshID: MeshID

    init?(profile: WorkspaceProfile, rawMeshID: String) {
        guard WorkspaceNativeFeatureRoute(profile: profile) == .warRoomDashboard,
              let meshID = try? MeshID(validating: rawMeshID) else { return nil }
        self.meshID = meshID
    }
}

struct WarRoomDashboardHost: View {
    @StateObject private var credentialModel: WarRoomDashboardCredentialModel
    private let dashboardService: any WarRoomDashboardServicing
    let profile: WorkspaceProfile
    let onClose: () -> Void

    @State private var meshIDInput = ""
    @State private var selectedMeshID: MeshID?
    @State private var validationMessage: String?
    @State private var isCredentialRemovalPresented = false

    init(profile: WorkspaceProfile, onClose: @escaping () -> Void) {
        let vault = KeychainCredentialVault()
        _credentialModel = StateObject(wrappedValue: WarRoomDashboardCredentialModel(
            profile: profile,
            service: DefaultWorkspaceConnectionService(credentialVault: vault)
        ))
        dashboardService = DefaultWarRoomDashboardService(credentialVault: vault)
        self.profile = profile
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("War Room")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Workspace", action: onClose)
                    }
                    if credentialModel.phase == .ready {
                        ToolbarItem(placement: .destructiveAction) {
                            Button("Remove credential", role: .destructive) {
                                isCredentialRemovalPresented = true
                            }
                        }
                    }
                    if selectedMeshID != nil {
                        ToolbarItem(placement: .secondaryAction) {
                            Button("Change mesh", action: resetMeshSelection)
                        }
                    }
                }
        }
        .tint(ThoxTheme.accent)
        .task(id: profile.id) { await credentialModel.refresh() }
        .onDisappear { credentialModel.cancel() }
        .confirmationDialog(
            "Remove this War Room credential?",
            isPresented: $isCredentialRemovalPresented,
            titleVisibility: .visible
        ) {
            Button("Remove Credential", role: .destructive) {
                resetMeshSelection()
                Task { await credentialModel.removeCredential() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the workspace credential from this device's Keychain. It does not contact MeshStack or delete server-side data.")
        }
        .accessibilityIdentifier("war-room-dashboard-host")
    }

    @ViewBuilder
    private var content: some View {
        if WorkspaceNativeFeatureRoute(profile: profile) != .warRoomDashboard {
            unavailableContent
        } else {
            switch credentialModel.phase {
            case .loading:
                ProgressView("Checking secure credential storage…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("war-room-credential-loading")
            case .credentialRequired:
                credentialContent
            case .ready:
                if let selectedMeshID {
                    LoadedWarRoomDashboard(
                        profile: profile,
                        meshID: selectedMeshID,
                        service: dashboardService
                    )
                } else {
                    meshSelectionContent
                }
            case .failed(let message):
                stateContent(
                    icon: "exclamationmark.triangle.fill",
                    title: "Secure storage unavailable",
                    detail: message
                ) {
                    Button("Try again") { Task { await credentialModel.refresh() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var credentialContent: some View {
        stateSurface {
            Label("War Room credential required", systemImage: "key.fill")
                .font(.title2.weight(.semibold))
            Text("Add the bearer token for this workspace. It is stored only in this device's non-synchronizing Keychain and is never written to workspace metadata.")
                .foregroundStyle(.secondary)
            SecureField("Bearer token", text: $credentialModel.credentialEntry)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
                .privacySensitive()
                .accessibilityIdentifier("war-room-credential")
            if let message = credentialModel.message {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("war-room-credential-error")
            }
            Button("Save credential") { Task { await credentialModel.saveCredential() } }
                .buttonStyle(.borderedProminent)
                .disabled(credentialModel.credentialEntry.isEmpty)
                .accessibilityIdentifier("save-war-room-credential")
        }
        .accessibilityIdentifier("war-room-credential-required")
    }

    private var meshSelectionContent: some View {
        stateSurface {
            Label("Select a private mesh", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.title2.weight(.semibold))
            Text("Enter the canonical mesh identifier supplied by your administrator. It is retained only while this dashboard is open and is never shown in dashboard results.")
                .foregroundStyle(.secondary)
            meshIDField
            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("war-room-mesh-validation")
            }
            Button("Open read-only dashboard", action: openDashboard)
                .buttonStyle(.borderedProminent)
                .disabled(meshIDInput.isEmpty)
                .accessibilityHint("Validates the mesh identifier before requesting read-only status")
                .accessibilityIdentifier("open-war-room-dashboard")
        }
        .accessibilityIdentifier("war-room-mesh-selection")
    }

    @ViewBuilder
    private var meshIDField: some View {
        #if os(iOS)
        SecureField("Mesh identifier", text: $meshIDInput)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
            .privacySensitive()
            .accessibilityIdentifier("war-room-mesh-id")
        #else
        SecureField("Mesh identifier", text: $meshIDInput)
            .textFieldStyle(.roundedBorder)
            .privacySensitive()
            .accessibilityIdentifier("war-room-mesh-id")
        #endif
    }

    private var unavailableContent: some View {
        stateContent(
            icon: "lock.shield",
            title: "Dashboard unavailable",
            detail: "This workspace does not advertise the read-only War Room status capability."
        ) { EmptyView() }
            .accessibilityIdentifier("war-room-route-unavailable")
    }

    private func stateContent<Actions: View>(
        icon: String,
        title: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        stateSurface {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(ThoxTheme.accent)
                .accessibilityHidden(true)
            Text(title).font(.title2.weight(.semibold))
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
            actions()
        }
    }

    private func stateSurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            ThoxTheme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) { content() }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(24)
                .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(ThoxTheme.separator) }
                .padding()
        }
    }

    private func openDashboard() {
        guard let selection = WarRoomDashboardRouteSelection(
            profile: profile,
            rawMeshID: meshIDInput
        ) else {
            validationMessage = "Enter a canonical mesh identifier. No identifier was retained in this error."
            return
        }
        selectedMeshID = selection.meshID
        meshIDInput.removeAll(keepingCapacity: false)
        validationMessage = nil
    }

    private func resetMeshSelection() {
        selectedMeshID = nil
        meshIDInput.removeAll(keepingCapacity: false)
        validationMessage = nil
    }
}

private struct LoadedWarRoomDashboard: View {
    @StateObject private var model: WarRoomDashboardModel

    init(
        profile: WorkspaceProfile,
        meshID: MeshID,
        service: any WarRoomDashboardServicing
    ) {
        _model = StateObject(wrappedValue: WarRoomDashboardModel(
            profile: profile,
            meshID: meshID,
            service: service
        ))
    }

    var body: some View { WarRoomDashboardView(model: model) }
}

@MainActor
private final class WarRoomDashboardCredentialModel: ObservableObject {
    enum Phase: Equatable { case loading, credentialRequired, ready, failed(String) }

    @Published private(set) var phase: Phase = .loading
    @Published var credentialEntry = ""
    @Published private(set) var message: String?

    private let profile: WorkspaceProfile
    private let service: any WorkspaceConnectionServicing
    private var generation = 0

    init(profile: WorkspaceProfile, service: any WorkspaceConnectionServicing) {
        self.profile = profile
        self.service = service
    }

    func refresh() async {
        generation += 1
        let activeGeneration = generation
        phase = .loading
        message = nil
        do {
            let hasCredential = try await service.hasCredential(for: profile.id)
            try Task.checkCancellation()
            guard generation == activeGeneration else { return }
            phase = hasCredential ? .ready : .credentialRequired
        } catch is CancellationError {
            return
        } catch {
            guard generation == activeGeneration else { return }
            phase = .failed("Secure credential storage is unavailable on this device.")
        }
    }

    func saveCredential() async {
        let submitted = credentialEntry
        credentialEntry.removeAll(keepingCapacity: false)
        message = nil
        generation += 1
        let activeGeneration = generation
        phase = .loading
        do {
            try await service.storeCredential(submitted, for: profile.id)
            try Task.checkCancellation()
            guard generation == activeGeneration else { return }
            phase = .ready
        } catch is CancellationError {
            return
        } catch {
            guard generation == activeGeneration else { return }
            message = error as? WorkspaceConnectionServiceError == .invalidCredential
                ? WorkspaceConnectionServiceError.invalidCredential.localizedDescription
                : "Secure credential storage is unavailable on this device."
            phase = .credentialRequired
        }
    }

    func removeCredential() async {
        generation += 1
        let activeGeneration = generation
        credentialEntry.removeAll(keepingCapacity: false)
        message = nil
        phase = .loading
        do {
            try await service.removeCredential(for: profile.id)
            try Task.checkCancellation()
            guard generation == activeGeneration else { return }
            phase = .credentialRequired
        } catch is CancellationError {
            return
        } catch {
            guard generation == activeGeneration else { return }
            phase = .failed("Secure credential storage is unavailable on this device.")
        }
    }

    func cancel() {
        generation += 1
        credentialEntry.removeAll(keepingCapacity: false)
        message = nil
    }
}

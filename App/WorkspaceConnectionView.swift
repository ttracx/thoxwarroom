import SwiftUI
import WarRoomCore
import WarRoomOpenWebUI

struct WorkspaceConnectionView: View {
    @ObservedObject var model: WorkspaceConnectionModel
    @State private var isCredentialRemovalPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                provenanceCard
                connectionContent
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding()
        }
        .background(ThoxTheme.background.ignoresSafeArea())
        .navigationTitle("Provider connection")
        .tint(ThoxTheme.accent)
        .task(id: model.profile.id) {
            model.connect()
            await model.waitForCurrentOperation()
        }
        .onDisappear { model.cancel() }
        .confirmationDialog(
            "Remove this provider credential?",
            isPresented: $isCredentialRemovalPresented,
            titleVisibility: .visible
        ) {
            Button("Remove Credential", role: .destructive) {
                model.removeCredential()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the workspace credential from this device's Keychain. It does not contact the provider or delete server-side data.")
        }
    }

    private var provenanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.profile.displayName, systemImage: model.profile.endpoint.boundary.systemImage)
                .font(.title2.weight(.semibold))
            LabeledContent("Boundary", value: model.profile.endpoint.boundary.title)
            LabeledContent("Provider", value: model.profile.provider.displayName)
            LabeledContent("Endpoint", value: visibleOrigin)
            Label(
                model.profile.endpoint.boundary.connectionProvenance,
                systemImage: "location.shield.fill"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .connectionCard()
        .accessibilityIdentifier("connection-provenance")
    }

    @ViewBuilder
    private var connectionContent: some View {
        switch model.state {
        case .idle:
            stateCard(
                icon: "network",
                title: "Connection not tested",
                detail: "Public discovery and the protected model catalog have not been requested."
            ) {
                Button("Test connection") { model.connect() }
                    .buttonStyle(.borderedProminent)
            }
            .accessibilityIdentifier("connection-idle")
        case .loading:
            stateCard(
                icon: "arrow.triangle.2.circlepath",
                title: "Testing provider…",
                detail: "Checking public health, version, and configuration before any protected request."
            ) {
                ProgressView().controlSize(.large)
                Button("Cancel", role: .cancel) { model.cancel() }
                    .accessibilityIdentifier("cancel-connection")
            }
            .accessibilityIdentifier("connection-loading")
        case .credentialRequired(let provenance):
            VStack(alignment: .leading, spacing: 18) {
                publicDiscovery(provenance)
                credentialForm
            }
            .connectionCard()
            .accessibilityIdentifier("connection-credential-required")
        case .empty(let provenance):
            VStack(alignment: .leading, spacing: 18) {
                publicDiscovery(provenance)
                Label("No models available", systemImage: "tray")
                    .font(.title3.weight(.semibold))
                Text("The protected request succeeded, but this credential returned an empty model catalog.")
                    .foregroundStyle(.secondary)
                credentialActions
            }
            .connectionCard()
            .accessibilityIdentifier("connection-empty")
        case .success(let provenance, let models):
            VStack(alignment: .leading, spacing: 18) {
                publicDiscovery(provenance)
                Label("Protected models", systemImage: "lock.open.fill")
                    .font(.title3.weight(.semibold))
                ForEach(models, id: \.id) { model in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.name ?? model.id).font(.headline)
                        if model.name != nil {
                            Text(model.id).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                credentialActions
            }
            .connectionCard()
            .accessibilityIdentifier("connection-success")
        case .offline(let message):
            stateCard(
                icon: "wifi.slash",
                title: "Provider offline",
                detail: message
            ) {
                Button("Try again") { model.connect() }
                    .buttonStyle(.borderedProminent)
            }
            .accessibilityIdentifier("connection-offline")
        case .error(let message):
            stateCard(
                icon: "exclamationmark.triangle.fill",
                title: "Connection unavailable",
                detail: message
            ) {
                Button("Try again") { model.connect() }
                    .buttonStyle(.borderedProminent)
            }
            .accessibilityIdentifier("connection-error")
        }
    }

    private var credentialForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Provider credential required", systemImage: "key.fill")
                .font(.title3.weight(.semibold))
            Text("The public provider is reachable. Add a credential to request the protected model catalog. It is stored only in this device's Keychain.")
                .foregroundStyle(.secondary)
            SecureField("Bearer token", text: $model.credentialEntry)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
                .privacySensitive()
                .accessibilityIdentifier("provider-credential")
            if let message = model.credentialMessage {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("credential-error")
            }
            Button("Save and load models") { model.saveCredential() }
                .buttonStyle(.borderedProminent)
                .disabled(model.credentialEntry.isEmpty)
                .accessibilityIdentifier("save-provider-credential")
        }
    }

    private var credentialActions: some View {
        HStack {
            Button("Refresh") { model.connect() }
                .buttonStyle(.borderedProminent)
            Spacer()
            Button("Remove credential", role: .destructive) {
                isCredentialRemovalPresented = true
            }
            .accessibilityIdentifier("remove-provider-credential")
        }
    }

    private func publicDiscovery(_ provenance: WorkspaceConnectionProvenance) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Public discovery verified", systemImage: "checkmark.shield.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(ThoxTheme.accent)
            LabeledContent("Health", value: provenance.health.rawValue)
            LabeledContent("Deployment", value: provenance.deploymentName)
            LabeledContent("Version", value: provenance.version)
            if provenance.configurationVersion != provenance.version {
                LabeledContent("Configuration version", value: provenance.configurationVersion)
            }
            LabeledContent(
                "Authentication",
                value: provenance.authenticationRequired ? "Required" : "Not advertised"
            )
        }
    }

    private func stateCard<Actions: View>(
        icon: String,
        title: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 38))
                .foregroundStyle(ThoxTheme.accent)
                .accessibilityHidden(true)
            Text(title).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
            actions()
        }
        .frame(maxWidth: .infinity)
        .connectionCard()
    }

    private var visibleOrigin: String {
        guard let scheme = model.profile.endpoint.url.scheme,
              let host = model.profile.endpoint.url.host else {
            return "Validated endpoint"
        }
        if let port = model.profile.endpoint.url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }
}

private extension View {
    func connectionCard() -> some View {
        padding(22)
            .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(ThoxTheme.separator) }
    }
}

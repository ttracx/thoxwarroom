import SwiftUI
import WarRoomCore

struct WorkspaceOnboardingView: View {
    @ObservedObject var model: WorkspaceOnboardingModel
    let onOpenNativeFeature: (WorkspaceProfile) -> Void
    let onOpenHostedCompatibility: (WorkspaceProfile) -> Void
    let onOpenWorkspaceBrowser: (WorkspaceProfile) -> Void
    @FocusState private var focusedField: Field?

    private enum Field { case name, endpoint }

    var body: some View {
        NavigationStack {
            ZStack {
                ThoxTheme.background.ignoresSafeArea()
                content.frame(maxWidth: 680).padding()
            }
            .navigationTitle("Private workspace")
        }
        .tint(ThoxTheme.accent)
        .task {
            guard model.phase == .loading else { return }
            await model.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            stateCard(
                icon: "shield.lefthalf.filled",
                title: "Loading workspace…",
                detail: "Reading local configuration. No network request is made."
            ) { ProgressView().controlSize(.large) }
                .accessibilityIdentifier("workspace-loading")
        case .empty:
            stateCard(
                icon: "externaldrive.badge.plus",
                title: "No workspace configured",
                detail: "Choose where THOX may send requests. Local device is the default."
            ) {
                Button("Configure workspace") { model.beginConfiguration() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("configure-workspace")
            }
            .accessibilityIdentifier("workspace-empty")
        case .editing:
            configurationForm
        case .saving:
            stateCard(
                icon: "lock.shield",
                title: "Saving workspace…",
                detail: "The endpoint and boundary are being stored on this device."
            ) { ProgressView().controlSize(.large) }
                .accessibilityIdentifier("workspace-saving")
        case .ready(let configuration):
            WorkspaceReadyView(
                configuration: configuration,
                onOpenNativeFeature: { onOpenNativeFeature(configuration) },
                onOpenHostedCompatibility: {
                    onOpenHostedCompatibility(configuration)
                },
                onOpenWorkspaceBrowser: {
                    onOpenWorkspaceBrowser(configuration)
                },
                onRemove: { Task { await model.reset() } }
            )
        case .failed(let message):
            stateCard(
                icon: "exclamationmark.triangle",
                title: "Workspace unavailable",
                detail: message
            ) {
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("retry-workspace-load")
            }
            .accessibilityIdentifier("workspace-error")
        }
    }

    private var configurationForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Choose a data boundary", systemImage: "hand.raised.fill")
                        .font(.title2.weight(.semibold))
                    Text("THOX will not silently fall back to a hosted service. You can change this choice by removing the workspace.")
                        .foregroundStyle(.secondary)
                }
                boundaryPicker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Provider").font(.headline)
                    Picker("Provider", selection: $model.draft.providerKind) {
                        ForEach(WorkspaceProviderKind.allCases, id: \.rawValue) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("workspace-provider")
                    Text(model.draft.providerKind.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Workspace name").font(.headline)
                    TextField("Research workstation", text: $model.draft.name)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .name)
                        .accessibilityIdentifier("workspace-name")
                    Text("Endpoint").font(.headline).padding(.top, 4)
                    endpointField
                    Text(endpointHelp).font(.caption).foregroundStyle(.secondary)
                }
                if model.draft.boundary == .hosted {
                    Toggle(isOn: $model.draft.hasHostedDataTransferConsent) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Allow data transfer to this hosted service").font(.headline)
                            Text("Prompts, retrieved context, and model output may leave this device. This consent applies only to this workspace.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("hosted-transfer-consent")
                }
                if let message = model.validationMessage {
                    Label(message, systemImage: "exclamationmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("workspace-validation-error")
                }
                HStack {
                    Spacer()
                    Button("Save workspace") {
                        focusedField = nil
                        Task { await model.save() }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint("Validates and stores this workspace without testing the network connection")
                    .accessibilityIdentifier("save-workspace")
                }
            }
            .padding(24)
            .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(ThoxTheme.separator) }
        }
        .accessibilityIdentifier("workspace-form")
    }

    private var boundaryPicker: some View {
        VStack(spacing: 10) {
            ForEach(NetworkBoundary.allCases, id: \.rawValue) { boundary in
                Button { model.selectBoundary(boundary) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: boundary.systemImage)
                            .font(.title3)
                            .frame(width: 28)
                            .foregroundStyle(boundary == model.draft.boundary ? ThoxTheme.accent : .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(boundary.title).font(.headline)
                            Text(boundary.privacySummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: boundary == model.draft.boundary ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(boundary == model.draft.boundary ? ThoxTheme.accent : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(12)
                .background(
                    boundary == model.draft.boundary ? ThoxTheme.accent.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(boundary == model.draft.boundary ? ThoxTheme.accent : ThoxTheme.separator)
                }
                .accessibilityLabel("\(boundary.title). \(boundary.privacySummary)")
                .accessibilityValue(boundary == model.draft.boundary ? "Selected" : "Not selected")
                .accessibilityIdentifier("boundary-\(boundary.rawValue)")
            }
        }
    }

    @ViewBuilder
    private var endpointField: some View {
        #if os(iOS)
        TextField("http://127.0.0.1", text: $model.draft.endpoint)
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .focused($focusedField, equals: .endpoint)
            .accessibilityIdentifier("workspace-endpoint")
        #else
        TextField("http://127.0.0.1", text: $model.draft.endpoint)
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: .endpoint)
            .accessibilityIdentifier("workspace-endpoint")
        #endif
    }

    private var endpointHelp: String {
        switch model.draft.boundary {
        case .localMachine: "Use localhost or a loopback address. HTTP is allowed because traffic never leaves this device."
        case .privateNetwork: "Use the exact HTTPS address supplied by your organization. Unencrypted private-network HTTP is disabled."
        case .hosted: "Hosted endpoints must use HTTPS and require explicit consent below."
        }
    }

    private func stateCard<Actions: View>(
        icon: String,
        title: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundStyle(ThoxTheme.accent)
                .accessibilityHidden(true)
            Text(title).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
            actions()
        }
        .frame(maxWidth: 480)
        .padding(32)
        .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(ThoxTheme.separator) }
    }
}

private struct WorkspaceReadyView: View {
    let configuration: WorkspaceProfile
    let onOpenNativeFeature: () -> Void
    let onOpenHostedCompatibility: () -> Void
    let onOpenWorkspaceBrowser: () -> Void
    let onRemove: () -> Void
    @State private var isRemovalPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Workspace ready", systemImage: "checkmark.shield.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(ThoxTheme.accent)
            Text(configuration.displayName).font(.title3.weight(.semibold))
            LabeledContent("Data boundary", value: configuration.endpoint.boundary.title)
            LabeledContent("Endpoint", value: configuration.endpoint.url.absoluteString)
            Text(configuration.endpoint.boundary.privacySummary).font(.callout).foregroundStyle(.secondary)
            Divider()
            Label(
                "Configuration is stored locally. When added, provider credentials are stored separately in this device's Keychain and are never accepted in endpoint URLs.",
                systemImage: "lock.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack {
                if let nativeRoute = WorkspaceNativeFeatureRoute(profile: configuration) {
                    Button(nativeRoute.buttonTitle) {
                        onOpenNativeFeature()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("open-native-workspace-feature")
                }
                if configuration.supportsHostedCompatibilityOrigin {
                    Button("Open hosted compatibility workspace") {
                        onOpenHostedCompatibility()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Opens webui.thox.ai after your explicit hosted workspace authorization")
                    .accessibilityIdentifier("open-hosted-compatibility")
                }
                if configuration.supportsLocalWorkspaceBrowser {
                    Button("Browse local files") {
                        onOpenWorkspaceBrowser()
                    }
                    .accessibilityHint("Choose a local folder for a confined read-only text browser")
                    .accessibilityIdentifier("open-workspace-browser")
                }
                Spacer()
                Button("Remove workspace", role: .destructive) { isRemovalPresented = true }
                    .accessibilityIdentifier("remove-workspace")
            }
        }
        .padding(28)
        .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(ThoxTheme.separator) }
        .accessibilityIdentifier("workspace-ready")
        .confirmationDialog(
            "Remove this workspace from this device?",
            isPresented: $isRemovalPresented,
            titleVisibility: .visible
        ) {
            Button("Remove Workspace", role: .destructive, action: onRemove)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved endpoint, boundary, and workspace credential from this device. It does not contact the endpoint or delete server-side data.")
        }
    }

}

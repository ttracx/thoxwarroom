import SwiftUI
import UniformTypeIdentifiers
import WarRoomAppleInfrastructure
import WarRoomCore

@MainActor
struct WorkspaceAuditCenterHost: View {
    @StateObject private var model: WorkspaceAuditCenterModel
    let onClose: () -> Void

    init(profile: WorkspaceProfile, onClose: @escaping () -> Void) {
        let coordinator: (any WorkspaceAuditLifecycleCoordinating)?
        do {
            coordinator = WorkspaceAuditLifecycleCoordinator(
                policyStore: try EncryptedWorkspaceAuditPolicyStore(),
                lifecycle: try EncryptedDurableAuditEventStore()
            )
        } catch {
            coordinator = nil
        }
        _model = StateObject(wrappedValue: WorkspaceAuditCenterModel(
            workspaceID: profile.id,
            workspaceName: profile.displayName,
            coordinator: coordinator,
            applicationVersion: AuditCenterApplicationVersion.current
        ))
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            WorkspaceAuditCenterView(model: model)
                .navigationTitle("Audit policy & export")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Workspace", action: onClose)
                            .accessibilityIdentifier("close-audit-center")
                    }
                }
        }
        .workspaceReturnCommand(WorkspaceCommandAction("Return to Workspace", perform: onClose))
    }
}

struct WorkspaceAuditCenterView: View {
    @ObservedObject var model: WorkspaceAuditCenterModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var isExporterPresented = false

    var body: some View {
        ZStack {
            ThoxTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    workspaceProvenance
                    operationStatus
                    currentPolicy
                    policyEditor
                    exportSection
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(24)
            }
        }
        .tint(ThoxTheme.accent)
        .task(id: model.workspaceID) {
            guard model.phase == .idle else { return }
            model.load()
            await model.waitForCurrentOperation()
        }
        .onDisappear { model.cancelOperation() }
        .onChange(of: scenePhase) { _, phase in
            model.sceneDidChange(isAppForeground: phase == .active)
        }
        .onChange(of: model.exportDocument != nil) { _, isReady in
            if isReady { isExporterPresented = true }
        }
        .confirmationDialog(
            model.pendingConfirmation?.title ?? "Confirm audit policy action",
            isPresented: confirmationBinding,
            titleVisibility: .visible
        ) {
            if let confirmation = model.pendingConfirmation {
                Button(confirmation.actionTitle, role: .destructive) {
                    model.confirmPending(isAppForeground: scenePhase == .active)
                }
            }
            Button("Cancel", role: .cancel) { model.dismissConfirmation() }
        } message: {
            if let confirmation = model.pendingConfirmation {
                Text(confirmation.message)
            }
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: model.exportDocument,
            contentType: .json,
            defaultFilename: model.suggestedExportFilename
        ) { result in
            switch result {
            case .success:
                model.exportPresentationCompleted(succeeded: true)
            case .failure:
                model.exportPresentationCompleted(succeeded: false)
            }
        }
        .accessibilityIdentifier("workspace-audit-center")
    }

    private var workspaceProvenance: some View {
        surface {
            Label("Workspace audit controls", systemImage: "checkmark.shield")
                .font(.title2.weight(.semibold))
            LabeledContent("Workspace", value: model.workspaceName)
            LabeledContent("Workspace identity") {
                Text(model.workspaceID.rawValue.uuidString.lowercased())
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .privacySensitive()
            }
            Text("Every policy operation and exported event is checked against this workspace identity. These controls do not contact the configured provider.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("audit-workspace-provenance")
    }

    @ViewBuilder
    private var operationStatus: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .loading:
            statusBanner(icon: "lock.shield", text: "Loading encrypted policy…", progress: true)
        case .saving:
            statusBanner(icon: "lock.shield", text: "Saving confirmed policy…", progress: true)
        case .applying:
            statusBanner(icon: "trash.slash", text: "Applying confirmed policy…", progress: true)
        case .exporting:
            statusBanner(icon: "doc.badge.arrow.up", text: "Preparing bounded redacted snapshot…", progress: true)
        case .cancelled:
            statusBanner(icon: "xmark.circle", text: "The operation was cancelled.", progress: false)
        case .failed(let message):
            statusBanner(icon: "exclamationmark.triangle.fill", text: message, progress: false)
        case .ready:
            if let message = model.validationMessage {
                statusBanner(icon: "exclamationmark.circle.fill", text: message, progress: false)
            }
        }
    }

    private var currentPolicy: some View {
        surface {
            Text("Confirmed policy").font(.headline)
            if let policy = model.currentPolicy, let label = model.currentPolicyLabel {
                LabeledContent("Retention", value: label)
                    .accessibilityIdentifier("confirmed-retention")
                LabeledContent("Revision", value: String(policy.revision))
                LabeledContent("Confirmed", value: policy.confirmedAt.formatted())
                LabeledContent(
                    "Last applied",
                    value: policy.lastAppliedAt?.formatted() ?? "Never"
                )
                if let result = model.lastRetentionResult {
                    Label(
                        "Applied: \(result.retainedEventCount) retained, \(result.prunedEventCount) pruned.",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(ThoxTheme.accent)
                    .accessibilityIdentifier("retention-result")
                }
            } else {
                Label("No retention policy is configured", systemImage: "hand.raised.fill")
                    .font(.headline)
                    .accessibilityIdentifier("retention-not-configured")
                Text("Nothing is pruned automatically. Choose and explicitly confirm a policy before application becomes available.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var policyEditor: some View {
        surface {
            Text("Retention choice").font(.headline)
            Picker("Retention choice", selection: $model.retentionMode) {
                ForEach(WorkspaceAuditRetentionMode.allCases, id: \.rawValue) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("audit-retention-mode")

            if model.retentionMode == .finite {
                Stepper(value: $model.finiteDays, in: AuditRetentionDays.minimum...AuditRetentionDays.maximum) {
                    LabeledContent("Duration", value: "\(model.finiteDays) days")
                }
                .accessibilityLabel("Finite retention duration")
                .accessibilityValue("\(model.finiteDays) days")
                .accessibilityIdentifier("audit-retention-days")
            } else {
                Text("Indefinite retention keeps audit events until a different policy is explicitly confirmed and applied.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("audit-indefinite-explanation")
            }

            Text("Saving records the exact choice but does not prune. Applying is a separate foreground-only destructive action.")
                .font(.caption)
                .foregroundStyle(.secondary)

            actionRow
        }
    }

    private var actionRow: some View {
        HStack {
            Button("Save policy") { model.prepareSaveConfirmation() }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSave)
                .accessibilityHint("Shows a destructive confirmation containing the exact retention choice before saving")
                .accessibilityIdentifier("save-audit-policy")
            Button("Apply confirmed policy", role: .destructive) {
                model.prepareApplyConfirmation(isAppForeground: scenePhase == .active)
            }
            .buttonStyle(.bordered)
            .disabled(!model.canApply || scenePhase != .active)
            .accessibilityHint("May permanently prune audit events after an exact confirmation")
            .accessibilityIdentifier("apply-audit-policy")
            if model.phase.isBusy {
                Button("Cancel", role: .cancel) { model.cancelOperation() }
                    .accessibilityIdentifier("cancel-audit-operation")
            }
            Spacer()
            if model.canLoad {
                Button("Reload policy") { model.load() }
                    .accessibilityIdentifier("reload-audit-policy")
            }
        }
    }

    private var exportSection: some View {
        surface {
            Text("Redacted export").font(.headline)
            Text("Prepare up to \(AuditExportLimit.standard.rawValue) redacted events in memory. The app creates no plaintext temporary file; the system exporter writes only to the destination you select.")
                .foregroundStyle(.secondary)
            Button("Choose export destination") { model.prepareExport() }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canExport)
                .accessibilityHint("Prepares a bounded redacted JSON snapshot and opens the system file picker")
                .accessibilityIdentifier("export-redacted-audit")
        }
    }

    private func statusBanner(icon: String, text: String, progress: Bool) -> some View {
        HStack(spacing: 12) {
            if progress {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: icon).accessibilityHidden(true)
            }
            Text(text).font(.callout)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(ThoxTheme.separator) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("audit-operation-status")
    }

    private func surface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(ThoxTheme.separator) }
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { model.pendingConfirmation != nil },
            set: { isPresented in
                if !isPresented { model.dismissConfirmation() }
            }
        )
    }
}

private enum AuditCenterApplicationVersion {
    static var current: String {
        guard let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String,
        !version.isEmpty else {
            return "unknown"
        }
        return version
    }
}

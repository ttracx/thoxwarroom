import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WarRoomCore

enum WorkspaceAuditRetentionMode: String, CaseIterable, Equatable, Sendable {
    case finite
    case indefinite

    var title: String {
        switch self {
        case .finite: "Finite"
        case .indefinite: "Indefinite"
        }
    }
}

struct WorkspaceAuditCenterRouteSelection: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let workspaceName: String

    init(profile: WorkspaceProfile) {
        workspaceID = profile.id
        workspaceName = profile.displayName
    }
}

struct WorkspaceAuditExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) throws {
        guard !data.isEmpty,
              data.count <= RedactedAuditExportSnapshot.maximumEncodedBytes else {
            throw AuditLifecycleError.exportTooLarge(
                limit: RedactedAuditExportSnapshot.maximumEncodedBytes
            )
        }
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
final class WorkspaceAuditCenterModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case saving
        case applying
        case exporting
        case cancelled
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .loading, .saving, .applying, .exporting: true
            case .idle, .ready, .cancelled, .failed: false
            }
        }
    }

    enum Confirmation: Equatable, Identifiable {
        case save(AuditRetentionPolicy)
        case apply(AuditRetentionPolicy, revision: UInt64)

        var id: String {
            switch self {
            case .save(let policy): "save-\(Self.label(for: policy))"
            case .apply(let policy, let revision):
                "apply-\(revision)-\(Self.label(for: policy))"
            }
        }

        var title: String {
            switch self {
            case .save(let policy):
                "Save \(Self.label(for: policy)) retention?"
            case .apply(let policy, _):
                "Apply \(Self.label(for: policy)) retention now?"
            }
        }

        var actionTitle: String {
            switch self {
            case .save(let policy): "Save \(Self.label(for: policy)) Policy"
            case .apply(let policy, _): "Apply \(Self.label(for: policy)) Now"
            }
        }

        var message: String {
            switch self {
            case .save(let policy):
                "This confirms \(Self.label(for: policy)) retention for this exact workspace. Saving does not prune audit history."
            case .apply(let policy, _):
                "This applies the confirmed \(Self.label(for: policy)) policy to this exact workspace and may permanently prune older audit events."
            }
        }

        var retention: AuditRetentionPolicy {
            switch self {
            case .save(let policy), .apply(let policy, _): policy
            }
        }

        static func label(for policy: AuditRetentionPolicy) -> String {
            switch policy {
            case .finite(let days): "\(days.rawValue)-day"
            case .indefinite: "indefinite"
            }
        }
    }

    static let loadFailureMessage =
        "Encrypted audit policy could not be verified. No retention operation was performed."
    static let saveFailureMessage =
        "The audit policy could not be saved. No retention operation was performed."
    static let applyFailureMessage =
        "The confirmed audit policy could not be applied. Audit history may be unchanged; verify it before retrying."
    static let exportFailureMessage =
        "The redacted audit snapshot could not be prepared. No export file was created."

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var currentPolicy: ConfirmedWorkspaceAuditPolicy?
    @Published private(set) var pendingConfirmation: Confirmation?
    @Published private(set) var exportDocument: WorkspaceAuditExportDocument?
    @Published private(set) var lastRetentionResult: AuditRetentionResult?
    @Published private(set) var validationMessage: String?
    @Published var retentionMode: WorkspaceAuditRetentionMode = .finite
    @Published var finiteDays = AuditRetentionDays.standard.rawValue

    let workspaceID: WorkspaceID
    let workspaceName: String

    private let coordinator: (any WorkspaceAuditLifecycleCoordinating)?
    private let applicationVersion: String
    private var operationTask: Task<Void, Never>?

    init(
        workspaceID: WorkspaceID,
        workspaceName: String,
        coordinator: (any WorkspaceAuditLifecycleCoordinating)?,
        applicationVersion: String
    ) {
        self.workspaceID = workspaceID
        self.workspaceName = workspaceName
        self.coordinator = coordinator
        self.applicationVersion = applicationVersion
    }

    deinit {
        operationTask?.cancel()
    }

    var canLoad: Bool { !phase.isBusy && coordinator != nil }
    var canSave: Bool { !phase.isBusy && coordinator != nil }
    var canApply: Bool { !phase.isBusy && coordinator != nil && currentPolicy != nil }
    var canExport: Bool { !phase.isBusy && coordinator != nil }

    var currentPolicyLabel: String? {
        currentPolicy.map { Confirmation.label(for: $0.retention) }
    }

    var suggestedExportFilename: String {
        "thox-audit-redacted-\(Self.filenameDateFormatter.string(from: Date()))"
    }

    func load() {
        guard canLoad, let coordinator else {
            if coordinator == nil { phase = .failed(Self.loadFailureMessage) }
            return
        }
        startOperation(phase: .loading) { [weak self] in
            guard let self else { return }
            do {
                let policy = try await coordinator.policy(for: workspaceID)
                try Task.checkCancellation()
                guard policy.map({ $0.workspaceID == self.workspaceID }) ?? true else {
                    return finishFailure(Self.loadFailureMessage)
                }
                currentPolicy = policy
                if let retention = policy?.retention { select(retention) }
                phase = .ready
            } catch is CancellationError {
                finishCancellation()
            } catch {
                finishFailure(Self.loadFailureMessage)
            }
        }
    }

    func prepareSaveConfirmation() {
        guard canSave else { return }
        validationMessage = nil
        do {
            pendingConfirmation = .save(try selectedRetention())
        } catch {
            validationMessage = "Choose a finite duration from 30 through 2555 days, or choose indefinite retention."
        }
    }

    func prepareApplyConfirmation(isAppForeground: Bool) {
        guard canApply, let policy = currentPolicy else { return }
        guard isAppForeground else {
            validationMessage = "Return to the foreground before applying this confirmed policy."
            return
        }
        validationMessage = nil
        pendingConfirmation = .apply(policy.retention, revision: policy.revision)
    }

    func dismissConfirmation() {
        pendingConfirmation = nil
    }

    func confirmPending(isAppForeground: Bool) {
        guard let confirmation = pendingConfirmation else { return }
        pendingConfirmation = nil
        switch confirmation {
        case .save(let retention):
            save(retention)
        case .apply(let retention, let revision):
            guard isAppForeground else {
                validationMessage = "Return to the foreground before applying this confirmed policy."
                return
            }
            apply(retention: retention, revision: revision)
        }
    }

    func prepareExport() {
        guard canExport, let coordinator else { return }
        exportDocument = nil
        validationMessage = nil
        startOperation(phase: .exporting) { [weak self] in
            guard let self else { return }
            do {
                let request = try AuditExportRequest(
                    workspaceID: workspaceID,
                    applicationVersion: applicationVersion,
                    limit: .standard
                )
                let snapshot = try await coordinator.exportSnapshot(
                    request,
                    generatedAt: Date()
                )
                try Task.checkCancellation()
                guard snapshot.workspaceID == workspaceID,
                      snapshot.applicationVersion == applicationVersion,
                      snapshot.events.count <= request.limit.rawValue else {
                    return finishFailure(Self.exportFailureMessage)
                }
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                exportDocument = try WorkspaceAuditExportDocument(data: data)
                phase = .ready
            } catch is CancellationError {
                finishCancellation()
            } catch {
                finishFailure(Self.exportFailureMessage)
            }
        }
    }

    func exportPresentationCompleted(succeeded: Bool) {
        exportDocument = nil
        if !succeeded {
            validationMessage = "Export was cancelled or could not be written to the selected destination."
        }
    }

    func cancelOperation() {
        guard phase.isBusy else { return }
        operationTask?.cancel()
        operationTask = nil
        phase = .cancelled
    }

    func sceneDidChange(isAppForeground: Bool) {
        if !isAppForeground, phase == .applying {
            cancelOperation()
            validationMessage = "Policy application was cancelled when the app left the foreground. Verify audit history before retrying."
        }
    }

    func waitForCurrentOperation() async {
        await operationTask?.value
    }

    private func save(_ retention: AuditRetentionPolicy) {
        guard canSave, let coordinator else { return }
        startOperation(phase: .saving) { [weak self] in
            guard let self else { return }
            do {
                let confirmed = try await coordinator.confirm(
                    retention,
                    for: workspaceID,
                    confirmedAt: Date()
                )
                try Task.checkCancellation()
                guard confirmed.workspaceID == workspaceID,
                      confirmed.retention == retention else {
                    return finishFailure(Self.saveFailureMessage)
                }
                currentPolicy = confirmed
                lastRetentionResult = nil
                phase = .ready
            } catch is CancellationError {
                finishCancellation()
            } catch {
                finishFailure(Self.saveFailureMessage)
            }
        }
    }

    private func apply(retention: AuditRetentionPolicy, revision: UInt64) {
        guard canApply,
              let coordinator,
              currentPolicy?.revision == revision,
              currentPolicy?.retention == retention else {
            validationMessage = "The confirmed policy changed. Reload it before applying retention."
            return
        }
        startOperation(phase: .applying) { [weak self] in
            guard let self else { return }
            do {
                let application = try await coordinator.applyConfirmedPolicy(
                    for: workspaceID,
                    asOf: Date()
                )
                try Task.checkCancellation()
                guard case .applied(let result, let appliedPolicy) = application,
                      result.workspaceID == workspaceID,
                      result.policy == retention,
                      appliedPolicy.workspaceID == workspaceID,
                      appliedPolicy.retention == retention else {
                    return finishFailure(Self.applyFailureMessage)
                }
                currentPolicy = appliedPolicy
                lastRetentionResult = result
                phase = .ready
            } catch is CancellationError {
                finishCancellation()
            } catch {
                finishFailure(Self.applyFailureMessage)
            }
        }
    }

    private func selectedRetention() throws -> AuditRetentionPolicy {
        switch retentionMode {
        case .finite:
            return .finite(try AuditRetentionDays(rawValue: finiteDays))
        case .indefinite:
            return .indefinite
        }
    }

    private func select(_ retention: AuditRetentionPolicy) {
        switch retention {
        case .finite(let days):
            retentionMode = .finite
            finiteDays = days.rawValue
        case .indefinite:
            retentionMode = .indefinite
        }
    }

    private func startOperation(
        phase nextPhase: Phase,
        operation: @escaping @MainActor () async -> Void
    ) {
        guard !phase.isBusy else { return }
        validationMessage = nil
        phase = nextPhase
        operationTask = Task { await operation() }
    }

    private func finishCancellation() {
        phase = .cancelled
        operationTask = nil
    }

    private func finishFailure(_ message: String) {
        phase = .failed(message)
        operationTask = nil
    }

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

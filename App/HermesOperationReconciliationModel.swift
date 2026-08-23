import Foundation
import WarRoomAppleInfrastructure
import WarRoomCore

/// Narrow read-only seam used by the app. It intentionally exposes no append or transport API.
protocol HermesOperationReconciliationReading: Sendable {
    func reconciliationRecords(
        matching query: AuditedOperationReconciliationQuery
    ) async throws -> AuditedOperationReconciliationPage
}

extension EncryptedDurableAuditedOperationStore: HermesOperationReconciliationReading {}

struct HermesOperationReconciliationSnapshot: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let pending: AuditedOperationReconciliationPage
    let terminal: AuditedOperationReconciliationPage

    init(
        workspaceID: WorkspaceID,
        pending: AuditedOperationReconciliationPage,
        terminal: AuditedOperationReconciliationPage
    ) throws {
        guard pending.workspaceID == workspaceID,
              pending.status == .pending,
              terminal.workspaceID == workspaceID,
              terminal.status == .terminal else {
            throw AuditedOperationPersistenceError.invalidReconciliationPage
        }
        self.workspaceID = workspaceID
        self.pending = pending
        self.terminal = terminal
    }

    var isEmpty: Bool { pending.records.isEmpty && terminal.records.isEmpty }
}

@MainActor
final class HermesOperationReconciliationModel: ObservableObject {
    enum Phase: Equatable {
        case unavailable(String)
        case idle
        case loading
        case loaded(HermesOperationReconciliationSnapshot)
        case failed(String)
        case cancelled
    }

    @Published private(set) var phase: Phase

    let workspaceID: WorkspaceID
    let workspaceName: String

    private let reader: (any HermesOperationReconciliationReading)?
    private var loadTask: Task<Void, Never>?
    private var generation = 0

    init(
        workspaceID: WorkspaceID,
        workspaceName: String,
        reader: (any HermesOperationReconciliationReading)?
    ) {
        self.workspaceID = workspaceID
        self.workspaceName = workspaceName
        self.reader = reader
        phase = reader == nil
            ? .unavailable("Encrypted operation evidence is unavailable on this device.")
            : .idle
    }

    deinit {
        loadTask?.cancel()
    }

    var canLoad: Bool {
        reader != nil && loadTask == nil
    }

    /// Reads independent bounded pending and terminal pages. It never retries or mutates Hermes.
    func load() {
        guard canLoad, let reader else { return }
        generation += 1
        let activeGeneration = generation
        let requestedWorkspaceID = workspaceID
        phase = .loading
        loadTask = Task { [weak self] in
            do {
                let pending = try await reader.reconciliationRecords(matching: .init(
                    workspaceID: requestedWorkspaceID,
                    status: .pending
                ))
                try Task.checkCancellation()
                guard let self else { return }
                let terminal = try await reader.reconciliationRecords(matching: .init(
                    workspaceID: requestedWorkspaceID,
                    status: .terminal
                ))
                try Task.checkCancellation()
                let snapshot = try HermesOperationReconciliationSnapshot(
                    workspaceID: requestedWorkspaceID,
                    pending: pending,
                    terminal: terminal
                )
                guard activeGeneration == generation else { return }
                loadTask = nil
                phase = .loaded(snapshot)
            } catch is CancellationError {
                guard let self, activeGeneration == generation else { return }
                loadTask = nil
                phase = .cancelled
            } catch {
                guard let self, activeGeneration == generation else { return }
                // Storage errors are deliberately collapsed so paths, records, and key state cannot leak.
                loadTask = nil
                phase = .failed("Encrypted operation evidence could not be verified. No Hermes action was taken.")
            }
        }
    }

    func cancelLoading() {
        guard case .loading = phase else { return }
        phase = .cancelled
        loadTask?.cancel()
    }

    func waitForCurrentLoad() async {
        await loadTask?.value
    }
}

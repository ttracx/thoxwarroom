import Foundation
import WarRoomCore
import WarRoomHermes

/// Narrow application seam for the package's audited, one-shot mutation coordinator.
protocol HermesMutationExecuting: Sendable {
    func execute(_ request: HermesAuditedOperationRequest) async -> HermesAuditedOperationResult
}

extension HermesAuditedOperationCoordinator: HermesMutationExecuting {}

struct HermesMutationPrerequisites: Equatable, Sendable {
    let authorizationReady: Bool
    let credentialReady: Bool
    let auditStoreReady: Bool

    static let unavailable = HermesMutationPrerequisites(
        authorizationReady: false,
        credentialReady: false,
        auditStoreReady: false
    )

    var areReady: Bool {
        authorizationReady && credentialReady && auditStoreReady
    }
}

enum HermesMutationReviewOption: String, CaseIterable, Equatable, Sendable {
    case approveOnce
    case approveSession
    case approveAlways
    case deny
    case stop

    var label: String {
        switch self {
        case .approveOnce: "Approve once"
        case .approveSession: "Approve for session"
        case .approveAlways: "Always approve"
        case .deny: "Deny"
        case .stop: "Stop run"
        }
    }

    var isDestructiveOrPersistent: Bool {
        self == .approveAlways || self == .deny || self == .stop
    }

    fileprivate var choice: HermesApprovalChoice? {
        switch self {
        case .approveOnce: .once
        case .approveSession: .session
        case .approveAlways: .always
        case .deny: .deny
        case .stop: nil
        }
    }
}

struct HermesMutationReviewContext: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let workspaceName: String
    let runID: HermesRunID
    let option: HermesMutationReviewOption
    let resolveAll: Bool
    let correlationID: AuditedOperationCorrelationID
}

@MainActor
final class HermesMutationReviewModel: ObservableObject {
    enum Phase: Equatable {
        case unavailable(String)
        case ready
        case confirming(HermesMutationReviewContext)
        case submitting(HermesMutationReviewContext)
        case succeeded(String)
        case failed(String)
        case cancelled
        case indeterminate(String)
    }

    @Published var selectedOption: HermesMutationReviewOption = .approveOnce
    @Published var resolveAll = false
    @Published private(set) var phase: Phase

    let workspaceID: WorkspaceID
    let workspaceName: String

    private let prerequisites: HermesMutationPrerequisites
    private let executor: (any HermesMutationExecuting)?
    private var operationTask: Task<Void, Never>?
    private var generation = 0

    init(
        workspaceID: WorkspaceID,
        workspaceName: String,
        prerequisites: HermesMutationPrerequisites,
        executor: (any HermesMutationExecuting)?
    ) {
        self.workspaceID = workspaceID
        self.workspaceName = workspaceName
        self.prerequisites = prerequisites
        self.executor = executor
        phase = Self.initialPhase(prerequisites: prerequisites, hasExecutor: executor != nil)
    }

    deinit {
        operationTask?.cancel()
    }

    func canPrepare(runIDInput: String) -> Bool {
        guard prerequisites.areReady, executor != nil,
              HermesRunID(rawValue: runIDInput.trimmingCharacters(in: .whitespacesAndNewlines)) != nil else {
            return false
        }
        guard case .ready = phase else { return false }
        return true
    }

    /// Creates a fresh, visible correlation ID but performs no transport operation.
    func prepare(runIDInput: String) {
        guard canPrepare(runIDInput: runIDInput),
              let runID = HermesRunID(
                rawValue: runIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
              ) else { return }

        phase = .confirming(HermesMutationReviewContext(
            workspaceID: workspaceID,
            workspaceName: workspaceName,
            runID: runID,
            option: selectedOption,
            resolveAll: selectedOption == .stop ? false : resolveAll,
            correlationID: AuditedOperationCorrelationID(rawValue: UUID())
        ))
    }

    /// Executes only the exact context that the user reviewed. There is no retry path.
    func confirm() {
        guard prerequisites.areReady, let executor,
              case .confirming(let context) = phase else { return }

        generation += 1
        let activeGeneration = generation
        phase = .submitting(context)
        let request = Self.request(for: context)
        operationTask = Task { [weak self] in
            let result = await executor.execute(request)
            guard let self, activeGeneration == generation else { return }
            phase = Self.phase(for: result)
            operationTask = nil
        }
    }

    func cancelConfirmation() {
        guard case .confirming = phase else { return }
        phase = .ready
    }

    func cancelSubmission() {
        guard case .submitting = phase else { return }
        operationTask?.cancel()
    }

    /// Starts a new deliberate review. This never reuses or retries the prior request.
    func beginNewReview() {
        guard operationTask == nil else { return }
        phase = Self.initialPhase(prerequisites: prerequisites, hasExecutor: executor != nil)
    }

    func waitForCurrentOperation() async {
        await operationTask?.value
    }

    private static func initialPhase(
        prerequisites: HermesMutationPrerequisites,
        hasExecutor: Bool
    ) -> Phase {
        guard prerequisites.authorizationReady else {
            return .unavailable("Mutation authorization has not been verified for this workspace.")
        }
        guard prerequisites.credentialReady else {
            return .unavailable("A verified workspace credential is required for mutations.")
        }
        guard prerequisites.auditStoreReady, hasExecutor else {
            return .unavailable("Durable audit protection is not ready. Mutations remain disabled.")
        }
        return .ready
    }

    private static func request(
        for context: HermesMutationReviewContext
    ) -> HermesAuditedOperationRequest {
        let operation: HermesAuditedOperation
        if let choice = context.option.choice {
            operation = .approval(
                runID: context.runID,
                request: HermesApprovalRequest(choice: choice, resolveAll: context.resolveAll)
            )
        } else {
            operation = .stop(runID: context.runID)
        }
        return HermesAuditedOperationRequest(
            workspaceID: context.workspaceID,
            correlationID: context.correlationID,
            operation: operation
        )
    }

    private static func phase(for result: HermesAuditedOperationResult) -> Phase {
        switch result {
        case .completed(.approval):
            return .succeeded("The reviewed approval decision completed and its outcome is durable.")
        case .completed(.stop):
            return .succeeded("The reviewed stop request completed and its outcome is durable.")
        case .cancelledBeforeIntent, .cancelledBeforeTransport:
            return .cancelled
        case .intentAuditFailed, .outcomeAuditFailedBeforeTransport:
            return .failed("The operation was not sent because durable audit protection failed.")
        case .replayRejected:
            return .failed("The operation was rejected because its correlation identifier was already used.")
        case .transportFailed:
            return .indeterminate("Hermes did not return a verifiable result. Review durable audit history before taking another action.")
        case .indeterminate:
            return .indeterminate("The result cannot be determined safely. Review Hermes and durable audit history before taking another action.")
        }
    }
}

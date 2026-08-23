import Foundation
import WarRoomCore

/// A fully scoped Hermes mutation. Opaque run identifiers never enter audit metadata.
public enum HermesAuditedOperation: Equatable, Sendable {
    case approval(runID: HermesRunID, request: HermesApprovalRequest)
    case stop(runID: HermesRunID)
}

/// One explicit, one-shot request to coordinate a Hermes mutation and its audit evidence.
public struct HermesAuditedOperationRequest: Equatable, Sendable {
    public let workspaceID: WorkspaceID
    public let correlationID: AuditedOperationCorrelationID
    public let operation: HermesAuditedOperation

    public init(
        workspaceID: WorkspaceID,
        correlationID: AuditedOperationCorrelationID,
        operation: HermesAuditedOperation
    ) {
        self.workspaceID = workspaceID
        self.correlationID = correlationID
        self.operation = operation
    }
}

/// A validated successful transport response. Success is returned only after its outcome is durable.
public enum HermesAuditedOperationResponse: Equatable, Sendable {
    case approval(HermesApprovalResponse)
    case stop(HermesStopResponse)
}

/// Cases where transport may have mutated Hermes but the caller cannot safely claim a result.
public enum HermesAuditedOperationIndeterminateReason: Equatable, Sendable {
    case cancelledAfterTransportStarted
    case outcomeAuditFailedAfterTransport
}

/// Non-sensitive terminal state for an audited mutation attempt.
public enum HermesAuditedOperationResult: Equatable, Sendable {
    case completed(HermesAuditedOperationResponse)
    case intentAuditFailed
    case replayRejected
    case cancelledBeforeIntent
    case cancelledBeforeTransport
    case outcomeAuditFailedBeforeTransport
    /// The transport failed; this does not prove whether the server applied the mutation.
    case transportFailed
    case indeterminate(HermesAuditedOperationIndeterminateReason)
}

/// Coordinates credential-sensitive Hermes mutations behind durable, redacted audit evidence.
///
/// The coordinator never retries transport. Callers must preserve the same correlation
/// ID for any user-driven replay, which the durable store will reject after intent claim.
public struct HermesAuditedOperationCoordinator: Sendable {
    private let client: HermesAPIClient
    private let auditStore: any DurableAuditedOperationStore

    public init(
        client: HermesAPIClient,
        auditStore: any DurableAuditedOperationStore
    ) {
        self.client = client
        self.auditStore = auditStore
    }

    public func execute(
        _ request: HermesAuditedOperationRequest
    ) async -> HermesAuditedOperationResult {
        guard !Task.isCancelled else { return .cancelledBeforeIntent }
        guard let intent = makeAuditRecord(
            for: request,
            phase: .intent,
            outcome: .requested,
            transportAttempted: false
        ) else {
            return .intentAuditFailed
        }

        do {
            let claim = try await auditStore.appendIntent(
                intent,
                correlationID: request.correlationID
            )
            guard claim == .appended else { return .replayRejected }
        } catch {
            return .intentAuditFailed
        }

        guard !Task.isCancelled else {
            return await recordPreTransportCancellation(for: request)
        }

        do {
            let response: HermesAuditedOperationResponse
            switch request.operation {
            case .approval(let runID, let approvalRequest):
                response = .approval(try await client.approve(
                    runID: runID,
                    request: approvalRequest
                ))
            case .stop(let runID):
                response = .stop(try await client.stop(runID: runID))
            }

            if Task.isCancelled {
                return await recordIndeterminateCancellation(for: request)
            }
            let outcome: AuditOutcome = request.isDeny ? .denied : .succeeded
            guard await appendOutcome(
                for: request,
                outcome: outcome,
                transportAttempted: true
            ) else {
                return .indeterminate(.outcomeAuditFailedAfterTransport)
            }
            return .completed(response)
        } catch is CancellationError {
            return await recordIndeterminateCancellation(for: request)
        } catch {
            guard await appendOutcome(
                for: request,
                outcome: .failed,
                transportAttempted: true
            ) else {
                return .indeterminate(.outcomeAuditFailedAfterTransport)
            }
            return .transportFailed
        }
    }

    private func recordPreTransportCancellation(
        for request: HermesAuditedOperationRequest
    ) async -> HermesAuditedOperationResult {
        guard await appendOutcome(
            for: request,
            outcome: .cancelled,
            transportAttempted: false
        ) else {
            return .outcomeAuditFailedBeforeTransport
        }
        return .cancelledBeforeTransport
    }

    private func recordIndeterminateCancellation(
        for request: HermesAuditedOperationRequest
    ) async -> HermesAuditedOperationResult {
        guard await appendOutcome(
            for: request,
            outcome: .cancelled,
            transportAttempted: true
        ) else {
            return .indeterminate(.outcomeAuditFailedAfterTransport)
        }
        return .indeterminate(.cancelledAfterTransportStarted)
    }

    private func appendOutcome(
        for request: HermesAuditedOperationRequest,
        outcome: AuditOutcome,
        transportAttempted: Bool
    ) async -> Bool {
        guard let record = makeAuditRecord(
            for: request,
            phase: .outcome,
            outcome: outcome,
            transportAttempted: transportAttempted
        ) else { return false }

        let store = auditStore
        let correlationID = request.correlationID
        // Outcome persistence receives one independent attempt even when the caller's
        // task was cancelled after transport began. Transport is never retried here.
        return await Task.detached {
            do {
                try await store.appendOutcome(record, correlationID: correlationID)
                return true
            } catch {
                return false
            }
        }.value
    }

    private func makeAuditRecord(
        for request: HermesAuditedOperationRequest,
        phase: AuditPhase,
        outcome: AuditOutcome,
        transportAttempted: Bool
    ) -> PersistableAuditEvent? {
        var fields = [
            AuditField(
                key: "correlation_id",
                value: .string(request.correlationID.description),
                privacy: .nonSensitive
            ),
            AuditField(
                key: "operation",
                value: .string(request.operationName),
                privacy: .nonSensitive
            ),
        ]
        if case .approval(_, let approvalRequest) = request.operation {
            fields.append(AuditField(
                key: "choice",
                value: .string(approvalRequest.choice.rawValue),
                privacy: .nonSensitive
            ))
            fields.append(AuditField(
                key: "resolve_all",
                value: .boolean(approvalRequest.resolveAll),
                privacy: .nonSensitive
            ))
        }
        if phase == .outcome {
            fields.append(AuditField(
                key: "transport_attempted",
                value: .boolean(transportAttempted),
                privacy: .nonSensitive
            ))
        }

        return try? PersistableAuditEvent(event: AuditEvent(
            workspaceID: request.workspaceID,
            category: "hermes.operation",
            action: phase.rawValue,
            outcome: outcome,
            fields: fields
        ))
    }

    private enum AuditPhase: String {
        case intent
        case outcome
    }
}

private extension HermesAuditedOperationRequest {
    var operationName: String {
        switch operation {
        case .approval: "approval"
        case .stop: "stop"
        }
    }

    var isDeny: Bool {
        guard case .approval(_, let request) = operation else { return false }
        return request.choice == .deny
    }
}

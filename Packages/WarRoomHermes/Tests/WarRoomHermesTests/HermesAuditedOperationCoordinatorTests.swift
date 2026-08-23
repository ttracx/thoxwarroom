import Foundation
import XCTest
import WarRoomCore
@testable import WarRoomHermes

final class HermesAuditedOperationCoordinatorTests: XCTestCase {
    func testIntentIsDurableBeforeApprovalTransportAndOutcomeUsesAllowlist() async throws {
        let trace = OperationTrace()
        let transport = AuditedOperationTransport(
            mode: .response(approvalResponse(runID: "opaque-run-a", choice: .once)),
            trace: trace
        )
        let store = AuditedOperationStoreStub(trace: trace)
        let coordinator = try makeCoordinator(transport: transport, store: store)
        let request = try operationRequest(
            operation: .approval(
                runID: runID("opaque-run-a"),
                request: HermesApprovalRequest(choice: .once)
            )
        )

        let result = await coordinator.execute(request)

        guard case .completed(.approval(let response)) = result else {
            return XCTFail("Expected audited approval completion")
        }
        XCTAssertEqual(response.choice, .once)
        let traceValues = await trace.values
        XCTAssertEqual(traceValues, ["intent", "transport", "outcome"])
        let events = await store.events
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].event.outcome, .requested)
        XCTAssertEqual(events[1].event.outcome, .succeeded)
        XCTAssertEqual(Set(events[0].event.metadata.keys), [
            "choice", "correlation_id", "operation", "resolve_all",
        ])
        XCTAssertEqual(Set(events[1].event.metadata.keys), [
            "choice", "correlation_id", "operation", "resolve_all", "transport_attempted",
        ])
        let encodedEvents = try JSONEncoder().encode(events)
        XCTAssertFalse(String(decoding: encodedEvents, as: UTF8.self).contains("opaque-run-a"))
    }

    func testIntentFailurePreventsTransport() async throws {
        let transport = AuditedOperationTransport(
            mode: .response(approvalResponse(runID: "opaque-run-a", choice: .once))
        )
        let store = AuditedOperationStoreStub(intentFails: true)
        let coordinator = try makeCoordinator(transport: transport, store: store)

        let result = await coordinator.execute(try operationRequest(
            operation: .approval(
                runID: runID("opaque-run-a"),
                request: HermesApprovalRequest(choice: .once)
            )
        ))

        XCTAssertEqual(result, .intentAuditFailed)
        let sendCount = await transport.sendCount
        XCTAssertEqual(sendCount, 0)
    }

    func testCorrelationReplayRejectsChangedWorkspaceRunAndChoiceWithoutSecondTransport() async throws {
        let transport = AuditedOperationTransport(
            mode: .response(approvalResponse(runID: "opaque-run-a", choice: .once))
        )
        let store = AuditedOperationStoreStub()
        let coordinator = try makeCoordinator(transport: transport, store: store)
        let correlationID = correlationID()
        let first = try operationRequest(
            correlationID: correlationID,
            operation: .approval(
                runID: runID("opaque-run-a"),
                request: HermesApprovalRequest(choice: .once)
            )
        )
        let replay = try operationRequest(
            workspaceID: WorkspaceID(rawValue: UUID()),
            correlationID: correlationID,
            operation: .approval(
                runID: runID("opaque-run-b"),
                request: HermesApprovalRequest(choice: .always, resolveAll: true)
            )
        )

        _ = await coordinator.execute(first)
        let replayResult = await coordinator.execute(replay)

        XCTAssertEqual(replayResult, .replayRejected)
        let sendCount = await transport.sendCount
        XCTAssertEqual(sendCount, 1)
    }

    func testOutcomeFailureAfterSuccessfulTransportIsIndeterminateAndNeverRetries() async throws {
        let transport = AuditedOperationTransport(mode: .response(stopResponse()))
        let store = AuditedOperationStoreStub(outcomeFails: true)
        let coordinator = try makeCoordinator(transport: transport, store: store)
        let request = try operationRequest(operation: .stop(runID: runID("opaque-run-a")))

        let result = await coordinator.execute(request)
        let replay = await coordinator.execute(request)

        XCTAssertEqual(result, .indeterminate(.outcomeAuditFailedAfterTransport))
        XCTAssertEqual(replay, .replayRejected)
        let sendCount = await transport.sendCount
        XCTAssertEqual(sendCount, 1)
    }

    func testTransportFailureAppendsFailedOutcomeWithoutClaimingSuccess() async throws {
        let transport = AuditedOperationTransport(mode: .failure)
        let store = AuditedOperationStoreStub()
        let coordinator = try makeCoordinator(transport: transport, store: store)

        let result = await coordinator.execute(try operationRequest(
            operation: .stop(runID: runID("opaque-run-a"))
        ))

        XCTAssertEqual(result, .transportFailed)
        let events = await store.events
        XCTAssertEqual(events.map(\.event.outcome), [.requested, .failed])
    }

    func testTransportFailureAndOutcomeFailureIsExplicitlyIndeterminate() async throws {
        let transport = AuditedOperationTransport(mode: .failure)
        let store = AuditedOperationStoreStub(outcomeFails: true)
        let coordinator = try makeCoordinator(transport: transport, store: store)

        let result = await coordinator.execute(try operationRequest(
            operation: .stop(runID: runID("opaque-run-a"))
        ))

        XCTAssertEqual(result, .indeterminate(.outcomeAuditFailedAfterTransport))
        let sendCount = await transport.sendCount
        XCTAssertEqual(sendCount, 1)
    }

    func testCancellationAfterTransportStartsIsIndeterminateAndDurablyCancelled() async throws {
        let transport = AuditedOperationTransport(mode: .suspendUntilCancelled)
        let store = AuditedOperationStoreStub()
        let coordinator = try makeCoordinator(transport: transport, store: store)
        let request = try operationRequest(operation: .stop(runID: runID("opaque-run-a")))

        let task = Task { await coordinator.execute(request) }
        while await transport.sendCount == 0 { await Task.yield() }
        task.cancel()
        let result = await task.value

        XCTAssertEqual(result, .indeterminate(.cancelledAfterTransportStarted))
        let sendCount = await transport.sendCount
        XCTAssertEqual(sendCount, 1)
        let events = await store.events
        XCTAssertEqual(events.map(\.event.outcome), [.requested, .cancelled])
        XCTAssertEqual(events.last?.event.metadata["transport_attempted"], .boolean(true))
    }

    func testAlreadyCancelledTaskDoesNotClaimIntentOrCallTransport() async throws {
        let transport = AuditedOperationTransport(mode: .response(stopResponse()))
        let store = AuditedOperationStoreStub()
        let coordinator = try makeCoordinator(transport: transport, store: store)
        let request = try operationRequest(operation: .stop(runID: runID("opaque-run-a")))

        let task = Task {
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch {}
            return await coordinator.execute(request)
        }
        task.cancel()
        let result = await task.value

        XCTAssertEqual(result, .cancelledBeforeIntent)
        let sendCount = await transport.sendCount
        let events = await store.events
        XCTAssertEqual(sendCount, 0)
        XCTAssertTrue(events.isEmpty)
    }

    func testDenyUsesDeniedOutcomeAndResponseScopeMismatchFailsClosed() async throws {
        let denyTransport = AuditedOperationTransport(
            mode: .response(approvalResponse(runID: "opaque-run-a", choice: .deny))
        )
        let denyStore = AuditedOperationStoreStub()
        let denyCoordinator = try makeCoordinator(transport: denyTransport, store: denyStore)
        let denyResult = await denyCoordinator.execute(try operationRequest(
            operation: .approval(
                runID: runID("opaque-run-a"),
                request: HermesApprovalRequest(choice: .deny)
            )
        ))
        guard case .completed(.approval) = denyResult else {
            return XCTFail("Expected deny response")
        }
        let denyEvents = await denyStore.events
        XCTAssertEqual(denyEvents.last?.event.outcome, .denied)

        let mismatchTransport = AuditedOperationTransport(
            mode: .response(approvalResponse(runID: "opaque-run-b", choice: .once))
        )
        let mismatchStore = AuditedOperationStoreStub()
        let mismatchCoordinator = try makeCoordinator(
            transport: mismatchTransport,
            store: mismatchStore
        )
        let mismatchResult = await mismatchCoordinator.execute(try operationRequest(
            operation: .approval(
                runID: runID("opaque-run-a"),
                request: HermesApprovalRequest(choice: .once)
            )
        ))
        XCTAssertEqual(mismatchResult, .transportFailed)
        let mismatchEvents = await mismatchStore.events
        XCTAssertEqual(mismatchEvents.last?.event.outcome, .failed)
    }

    private func makeCoordinator(
        transport: AuditedOperationTransport,
        store: AuditedOperationStoreStub
    ) throws -> HermesAuditedOperationCoordinator {
        HermesAuditedOperationCoordinator(
            client: HermesAPIClient(transport: transport, endpoint: try endpoint()),
            auditStore: store
        )
    }

    private func operationRequest(
        workspaceID: WorkspaceID = WorkspaceID(
            rawValue: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        ),
        correlationID: AuditedOperationCorrelationID? = nil,
        operation: HermesAuditedOperation
    ) throws -> HermesAuditedOperationRequest {
        HermesAuditedOperationRequest(
            workspaceID: workspaceID,
            correlationID: correlationID ?? self.correlationID(),
            operation: operation
        )
    }

    private func correlationID() -> AuditedOperationCorrelationID {
        AuditedOperationCorrelationID(
            rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        )
    }

    private func runID(_ value: String) -> HermesRunID {
        HermesRunID(rawValue: value)!
    }

    private func endpoint() throws -> ValidatedEndpoint {
        try EndpointValidator.validate(
            "http://127.0.0.1",
            declaredBoundary: .localMachine
        )
    }

    private func approvalResponse(runID: String, choice: HermesApprovalChoice) -> ProviderResponse {
        ProviderResponse(
            statusCode: 200,
            body: Data(
                """
                {"object":"hermes.run.approval_response","run_id":"\(runID)","choice":"\(choice.rawValue)","resolved":1}
                """.utf8
            )
        )
    }

    private func stopResponse() -> ProviderResponse {
        ProviderResponse(statusCode: 202, body: Data())
    }
}

private actor OperationTrace {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
}

private actor AuditedOperationTransport: ProviderTransport {
    enum Mode: Sendable {
        case response(ProviderResponse)
        case failure
        case suspendUntilCancelled
    }

    private let mode: Mode
    private let trace: OperationTrace?
    private(set) var sendCount = 0

    init(mode: Mode, trace: OperationTrace? = nil) {
        self.mode = mode
        self.trace = trace
    }

    func send(
        _ request: ProviderRequest,
        to endpoint: ValidatedEndpoint,
        credential: ProviderCredential?
    ) async throws -> ProviderResponse {
        sendCount += 1
        await trace?.append("transport")
        switch mode {
        case .response(let response): return response
        case .failure: throw AuditedOperationTestError.injectedFailure
        case .suspendUntilCancelled:
            try await Task.sleep(nanoseconds: 60_000_000_000)
            throw AuditedOperationTestError.injectedFailure
        }
    }
}

private actor AuditedOperationStoreStub: DurableAuditedOperationStore {
    private let intentFails: Bool
    private let outcomeFails: Bool
    private let trace: OperationTrace?
    private var claimed: Set<AuditedOperationCorrelationID> = []
    private var completed: Set<AuditedOperationCorrelationID> = []
    private(set) var events: [PersistableAuditEvent] = []

    init(
        intentFails: Bool = false,
        outcomeFails: Bool = false,
        trace: OperationTrace? = nil
    ) {
        self.intentFails = intentFails
        self.outcomeFails = outcomeFails
        self.trace = trace
    }

    func appendIntent(
        _ intent: PersistableAuditEvent,
        correlationID: AuditedOperationCorrelationID
    ) async throws -> AuditedOperationIntentAppendResult {
        if intentFails { throw AuditedOperationTestError.injectedFailure }
        guard claimed.insert(correlationID).inserted else { return .replayRejected }
        events.append(intent)
        await trace?.append("intent")
        return .appended
    }

    func appendOutcome(
        _ outcome: PersistableAuditEvent,
        correlationID: AuditedOperationCorrelationID
    ) async throws {
        if outcomeFails { throw AuditedOperationTestError.injectedFailure }
        guard claimed.contains(correlationID),
              completed.insert(correlationID).inserted,
              events.first(where: { $0.event.metadata["correlation_id"] == .string(correlationID.description) })?.event.workspaceID
                == outcome.event.workspaceID else {
            throw AuditedOperationTestError.invalidScope
        }
        events.append(outcome)
        await trace?.append("outcome")
    }
}

private enum AuditedOperationTestError: Error {
    case injectedFailure
    case invalidScope
}

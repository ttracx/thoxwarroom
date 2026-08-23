import XCTest
import WarRoomCore
import WarRoomHermes
@testable import ThoxWarRoom

@MainActor
final class HermesMutationReviewModelTests: XCTestCase {
    func testEveryPrerequisiteAndExecutorAreRequired() {
        let combinations = [
            HermesMutationPrerequisites(authorizationReady: false, credentialReady: true, auditStoreReady: true),
            HermesMutationPrerequisites(authorizationReady: true, credentialReady: false, auditStoreReady: true),
            HermesMutationPrerequisites(authorizationReady: true, credentialReady: true, auditStoreReady: false),
        ]

        for prerequisites in combinations {
            let model = makeModel(prerequisites: prerequisites, executor: MutationExecutorStub())
            XCTAssertFalse(model.canPrepare(runIDInput: "opaque-run"))
            guard case .unavailable = model.phase else {
                return XCTFail("An incomplete prerequisite set must fail closed")
            }
        }

        let noExecutor = makeModel(prerequisites: .readyForTests, executor: nil)
        XCTAssertFalse(noExecutor.canPrepare(runIDInput: "opaque-run"))
        guard case .unavailable = noExecutor.phase else {
            return XCTFail("A missing coordinator must fail closed")
        }
    }

    func testPreparingShowsExactScopeWithoutExecuting() async throws {
        let executor = MutationExecutorStub()
        let model = makeModel(prerequisites: .readyForTests, executor: executor)
        model.selectedOption = .approveSession
        model.resolveAll = true

        model.prepare(runIDInput: "opaque-run-42")

        let context = try confirmingContext(model.phase)
        XCTAssertEqual(context.workspaceID, workspaceID)
        XCTAssertEqual(context.workspaceName, "Research workspace")
        XCTAssertEqual(context.runID.rawValue, "opaque-run-42")
        XCTAssertEqual(context.option, .approveSession)
        XCTAssertTrue(context.resolveAll)
        let requestCount = await executor.requestCount
        XCTAssertEqual(requestCount, 0)
    }

    func testConfirmationExecutesReviewedRequestExactlyOnce() async throws {
        let executor = MutationExecutorStub(result: .completed(.approval(
            HermesApprovalResponse(
                object: "approval",
                runID: try XCTUnwrap(HermesRunID(rawValue: "opaque-run-42")),
                choice: .once,
                resolved: 1
            )
        )))
        let model = makeModel(prerequisites: .readyForTests, executor: executor)
        model.prepare(runIDInput: "opaque-run-42")
        let reviewed = try confirmingContext(model.phase)

        model.confirm()
        model.confirm()
        await model.waitForCurrentOperation()

        let requestCount = await executor.requestCount
        let lastRequest = await executor.lastRequest
        XCTAssertEqual(requestCount, 1)
        let request = try XCTUnwrap(lastRequest)
        XCTAssertEqual(request.workspaceID, workspaceID)
        XCTAssertEqual(request.correlationID, reviewed.correlationID)
        guard case .approval(let runID, let approval) = request.operation else {
            return XCTFail("Expected an approval operation")
        }
        XCTAssertEqual(runID.rawValue, "opaque-run-42")
        XCTAssertEqual(approval.choice, .once)
        XCTAssertFalse(approval.resolveAll)
        guard case .succeeded = model.phase else {
            return XCTFail("Expected a durable success state")
        }
    }

    func testStopReviewCannotCarryResolveAll() throws {
        let model = makeModel(prerequisites: .readyForTests, executor: MutationExecutorStub())
        model.selectedOption = .stop
        model.resolveAll = true

        model.prepare(runIDInput: "opaque-run")

        let context = try confirmingContext(model.phase)
        XCTAssertFalse(context.resolveAll)
        XCTAssertTrue(context.option.isDestructiveOrPersistent)
    }

    func testBackingOutDoesNotExecuteAndNewReviewGetsNewCorrelation() async throws {
        let executor = MutationExecutorStub()
        let model = makeModel(prerequisites: .readyForTests, executor: executor)
        model.selectedOption = .deny
        model.prepare(runIDInput: "opaque-run")
        let first = try confirmingContext(model.phase)

        model.cancelConfirmation()
        model.prepare(runIDInput: "opaque-run")
        let second = try confirmingContext(model.phase)

        XCTAssertNotEqual(first.correlationID, second.correlationID)
        let requestCount = await executor.requestCount
        XCTAssertEqual(requestCount, 0)
    }

    func testTerminalResultsUseBoundedSafeMessages() async {
        let unsafeRun = "raw-tool-output-must-not-appear"
        let cases: [(HermesAuditedOperationResult, (HermesMutationReviewModel.Phase) -> Bool)] = [
            (.intentAuditFailed, { if case .failed = $0 { true } else { false } }),
            (.transportFailed, { if case .indeterminate = $0 { true } else { false } }),
            (.indeterminate(.outcomeAuditFailedAfterTransport), { if case .indeterminate = $0 { true } else { false } }),
            (.cancelledBeforeTransport, { $0 == .cancelled }),
        ]

        for (result, matches) in cases {
            let model = makeModel(
                prerequisites: .readyForTests,
                executor: MutationExecutorStub(result: result)
            )
            model.prepare(runIDInput: unsafeRun)
            model.confirm()
            await model.waitForCurrentOperation()
            XCTAssertTrue(matches(model.phase))
            XCTAssertFalse(String(describing: model.phase).contains(unsafeRun))
        }
    }

    func testCancelSubmissionRequestsCancellationWithoutResubmitting() async {
        let executor = MutationExecutorStub(delayUntilCancelled: true)
        let model = makeModel(prerequisites: .readyForTests, executor: executor)
        model.prepare(runIDInput: "opaque-run")
        model.confirm()

        await Task.yield()
        model.cancelSubmission()
        await model.waitForCurrentOperation()

        XCTAssertEqual(model.phase, .cancelled)
        let requestCount = await executor.requestCount
        XCTAssertEqual(requestCount, 1)
    }

    private let workspaceID = WorkspaceID(
        rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    )

    private func makeModel(
        prerequisites: HermesMutationPrerequisites,
        executor: (any HermesMutationExecuting)?
    ) -> HermesMutationReviewModel {
        HermesMutationReviewModel(
            workspaceID: workspaceID,
            workspaceName: "Research workspace",
            prerequisites: prerequisites,
            executor: executor
        )
    }

    private func confirmingContext(
        _ phase: HermesMutationReviewModel.Phase
    ) throws -> HermesMutationReviewContext {
        guard case .confirming(let context) = phase else {
            throw MutationReviewTestError.expectedConfirmation
        }
        return context
    }
}

private extension HermesMutationPrerequisites {
    static let readyForTests = HermesMutationPrerequisites(
        authorizationReady: true,
        credentialReady: true,
        auditStoreReady: true
    )
}

private actor MutationExecutorStub: HermesMutationExecuting {
    private(set) var requests: [HermesAuditedOperationRequest] = []
    let result: HermesAuditedOperationResult
    let delayUntilCancelled: Bool

    init(
        result: HermesAuditedOperationResult = .cancelledBeforeTransport,
        delayUntilCancelled: Bool = false
    ) {
        self.result = result
        self.delayUntilCancelled = delayUntilCancelled
    }

    var requestCount: Int { requests.count }
    var lastRequest: HermesAuditedOperationRequest? { requests.last }

    func execute(_ request: HermesAuditedOperationRequest) async -> HermesAuditedOperationResult {
        requests.append(request)
        if delayUntilCancelled {
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                return .cancelledBeforeTransport
            }
        }
        return result
    }
}

private enum MutationReviewTestError: Error {
    case expectedConfirmation
}

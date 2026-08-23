import XCTest
import WarRoomCore
@testable import ThoxWarRoom

@MainActor
final class WorkspaceAuditCenterModelTests: XCTestCase {
    func testAbsentPolicyNeverOffersOrInvokesRetentionApplication() async {
        let coordinator = AuditLifecycleCoordinatorStub(policy: nil)
        let model = makeModel(coordinator: coordinator)

        model.load()
        await model.waitForCurrentOperation()
        model.prepareApplyConfirmation(isAppForeground: true)
        model.confirmPending(isAppForeground: true)

        XCTAssertEqual(model.phase, .ready)
        XCTAssertNil(model.currentPolicy)
        XCTAssertNil(model.pendingConfirmation)
        XCTAssertFalse(model.canApply)
        let applyCallCount = await coordinator.applyCallCount
        XCTAssertEqual(applyCallCount, 0)
    }

    func testFiniteSelectionIsValidatedAndIndefiniteIsExplicit() async {
        let model = makeModel(coordinator: AuditLifecycleCoordinatorStub())
        model.load()
        await model.waitForCurrentOperation()

        model.finiteDays = AuditRetentionDays.minimum - 1
        model.prepareSaveConfirmation()

        XCTAssertNil(model.pendingConfirmation)
        XCTAssertEqual(
            model.validationMessage,
            "Choose a finite duration from 30 through 2555 days, or choose indefinite retention."
        )

        model.finiteDays = AuditRetentionDays.maximum
        model.prepareSaveConfirmation()
        XCTAssertEqual(
            model.pendingConfirmation,
            .save(.finite(try! AuditRetentionDays(rawValue: AuditRetentionDays.maximum)))
        )

        model.dismissConfirmation()
        model.retentionMode = .indefinite
        model.prepareSaveConfirmation()
        XCTAssertEqual(model.pendingConfirmation, .save(.indefinite))
        XCTAssertEqual(model.pendingConfirmation?.actionTitle, "Save indefinite Policy")
    }

    func testSaveRequiresExactDestructiveConfirmationBeforePersistence() async throws {
        let coordinator = AuditLifecycleCoordinatorStub()
        let model = makeModel(coordinator: coordinator)
        model.load()
        await model.waitForCurrentOperation()
        model.finiteDays = 90

        model.prepareSaveConfirmation()

        let callsBeforeConfirmation = await coordinator.confirmCallCount
        XCTAssertEqual(callsBeforeConfirmation, 0)
        XCTAssertEqual(model.pendingConfirmation?.title, "Save 90-day retention?")
        XCTAssertEqual(model.pendingConfirmation?.actionTitle, "Save 90-day Policy")

        model.confirmPending(isAppForeground: true)
        await model.waitForCurrentOperation()

        let callsAfterConfirmation = await coordinator.confirmCallCount
        XCTAssertEqual(callsAfterConfirmation, 1)
        XCTAssertEqual(model.currentPolicy?.workspaceID, workspaceID)
        XCTAssertEqual(
            model.currentPolicy?.retention,
            .finite(try AuditRetentionDays(rawValue: 90))
        )
    }

    func testApplyRequiresConfirmedPolicyAndForegroundAtPreparationAndCommit() async throws {
        let policy = try makePolicy(retention: .indefinite)
        let coordinator = AuditLifecycleCoordinatorStub(policy: policy)
        let model = makeModel(coordinator: coordinator)
        model.load()
        await model.waitForCurrentOperation()

        model.prepareApplyConfirmation(isAppForeground: false)
        XCTAssertNil(model.pendingConfirmation)
        XCTAssertEqual(
            model.validationMessage,
            "Return to the foreground before applying this confirmed policy."
        )
        var applyCallCount = await coordinator.applyCallCount
        XCTAssertEqual(applyCallCount, 0)

        model.prepareApplyConfirmation(isAppForeground: true)
        XCTAssertEqual(model.pendingConfirmation?.title, "Apply indefinite retention now?")
        model.confirmPending(isAppForeground: false)
        applyCallCount = await coordinator.applyCallCount
        XCTAssertEqual(applyCallCount, 0)

        model.prepareApplyConfirmation(isAppForeground: true)
        model.confirmPending(isAppForeground: true)
        await model.waitForCurrentOperation()

        applyCallCount = await coordinator.applyCallCount
        XCTAssertEqual(applyCallCount, 1)
        XCTAssertEqual(model.lastRetentionResult?.policy, .indefinite)
        XCTAssertEqual(model.currentPolicy?.lastAppliedAt != nil, true)
    }

    func testNotConfiguredRaceFailsClosedInsteadOfReportingApplication() async throws {
        let coordinator = AuditLifecycleCoordinatorStub(
            policy: try makePolicy(retention: .indefinite),
            returnsNotConfiguredOnApply: true
        )
        let model = makeModel(coordinator: coordinator)
        model.load()
        await model.waitForCurrentOperation()

        model.prepareApplyConfirmation(isAppForeground: true)
        model.confirmPending(isAppForeground: true)
        await model.waitForCurrentOperation()

        XCTAssertEqual(model.phase, .failed(WorkspaceAuditCenterModel.applyFailureMessage))
        XCTAssertNil(model.lastRetentionResult)
    }

    func testCrossWorkspacePolicyIsRejectedWithFixedRedactedFailure() async throws {
        let otherID = WorkspaceID(
            rawValue: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        )
        let coordinator = AuditLifecycleCoordinatorStub(policy: try ConfirmedWorkspaceAuditPolicy(
            workspaceID: otherID,
            revision: 1,
            retention: .indefinite,
            confirmedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        let model = makeModel(coordinator: coordinator)

        model.load()
        await model.waitForCurrentOperation()

        XCTAssertEqual(model.phase, .failed(WorkspaceAuditCenterModel.loadFailureMessage))
        XCTAssertNil(model.currentPolicy)
    }

    func testFailedReloadClearsStalePolicyAndDisablesApplication() async throws {
        let coordinator = AuditLifecycleCoordinatorStub(
            policy: try makePolicy(retention: .indefinite)
        )
        let model = makeModel(coordinator: coordinator)
        model.load()
        await model.waitForCurrentOperation()
        XCTAssertTrue(model.canApply)

        let otherID = WorkspaceID(
            rawValue: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        )
        await coordinator.replacePolicy(try ConfirmedWorkspaceAuditPolicy(
            workspaceID: otherID,
            revision: 1,
            retention: .indefinite,
            confirmedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        model.load()
        await model.waitForCurrentOperation()

        XCTAssertNil(model.currentPolicy)
        XCTAssertFalse(model.canApply)
        XCTAssertFalse(model.canSave)
    }

    func testCancellationStopsLoadWithoutExposingUnderlyingState() async {
        let coordinator = AuditLifecycleCoordinatorStub(blocksPolicyLoad: true)
        let model = makeModel(coordinator: coordinator)

        model.load()
        await Task.yield()
        model.cancelOperation()
        await model.waitForCurrentOperation()

        XCTAssertEqual(model.phase, .cancelled)
        XCTAssertTrue(model.canLoad)
    }

    func testExportIsBoundedRedactedWorkspaceScopedAndInMemory() async throws {
        let snapshot = try makeSnapshot(workspaceID: workspaceID)
        let coordinator = AuditLifecycleCoordinatorStub(snapshot: snapshot)
        let model = makeModel(coordinator: coordinator)

        model.prepareExport()
        await model.waitForCurrentOperation()

        let request = await coordinator.lastExportRequest
        XCTAssertEqual(request?.workspaceID, workspaceID)
        XCTAssertEqual(request?.limit, .standard)
        XCTAssertEqual(request?.applicationVersion, "4.2.0")
        let document = try XCTUnwrap(model.exportDocument)
        XCTAssertLessThanOrEqual(
            document.data.count,
            RedactedAuditExportSnapshot.maximumEncodedBytes
        )
        let decoded = try JSONDecoder.iso8601.decode(
            RedactedAuditExportSnapshot.self,
            from: document.data
        )
        XCTAssertEqual(decoded.workspaceID, workspaceID)
        XCTAssertTrue(decoded.events.isEmpty)
    }

    func testUnsafeErrorsAreCollapsedAndUnrelatedRouteSelectionSurvives() async throws {
        let unsafe = "/Users/operator/private/token-secret"
        let coordinator = AuditLifecycleCoordinatorStub(errorMessage: unsafe)
        let model = makeModel(coordinator: coordinator)
        let profile = try makeProfile()
        let routeBeforeFailure = WorkspaceNativeFeatureRoute(profile: profile)

        model.load()
        await model.waitForCurrentOperation()

        XCTAssertEqual(model.phase, .failed(WorkspaceAuditCenterModel.loadFailureMessage))
        XCTAssertFalse(WorkspaceAuditCenterModel.loadFailureMessage.contains(unsafe))
        XCTAssertLessThan(WorkspaceAuditCenterModel.loadFailureMessage.utf8.count, 160)
        XCTAssertEqual(WorkspaceNativeFeatureRoute(profile: profile), routeBeforeFailure)
        let auditRoute = WorkspaceAuditCenterRouteSelection(profile: profile)
        XCTAssertEqual(auditRoute.workspaceID, profile.id)
        XCTAssertEqual(auditRoute.workspaceName, profile.displayName)
    }

    private let workspaceID = WorkspaceID(
        rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    )

    private func makeModel(
        coordinator: any WorkspaceAuditLifecycleCoordinating
    ) -> WorkspaceAuditCenterModel {
        WorkspaceAuditCenterModel(
            workspaceID: workspaceID,
            workspaceName: "Research workspace",
            coordinator: coordinator,
            applicationVersion: "4.2.0"
        )
    }

    private func makePolicy(
        retention: AuditRetentionPolicy
    ) throws -> ConfirmedWorkspaceAuditPolicy {
        try ConfirmedWorkspaceAuditPolicy(
            workspaceID: workspaceID,
            revision: 1,
            retention: retention,
            confirmedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func makeSnapshot(
        workspaceID: WorkspaceID
    ) throws -> RedactedAuditExportSnapshot {
        try RedactedAuditExportSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            workspaceID: workspaceID,
            occurredOnOrAfter: nil,
            occurredBefore: nil,
            applicationVersion: "4.2.0",
            events: [],
            truncated: false,
            integrity: AuditExportIntegrity(
                ledgerGeneration: 0,
                retainedEventCount: 0,
                lifetimeEventCount: 0,
                sourceHeadSHA256: String(repeating: "a", count: 64),
                snapshotSHA256: String(repeating: "b", count: 64)
            )
        )
    }

    private func makeProfile() throws -> WorkspaceProfile {
        try WorkspaceProfile(
            id: workspaceID,
            displayName: "Research workspace",
            endpoint: EndpointValidator.validate(
                "http://127.0.0.1",
                declaredBoundary: .localMachine
            ),
            provider: WorkspaceProviderKind.openWebUI.descriptor
        )
    }
}

private actor AuditLifecycleCoordinatorStub: WorkspaceAuditLifecycleCoordinating {
    private var storedPolicy: ConfirmedWorkspaceAuditPolicy?
    private let snapshot: RedactedAuditExportSnapshot?
    private let errorMessage: String?
    private let blocksPolicyLoad: Bool
    private let returnsNotConfiguredOnApply: Bool
    private(set) var confirmCallCount = 0
    private(set) var applyCallCount = 0
    private(set) var lastExportRequest: AuditExportRequest?

    init(
        policy: ConfirmedWorkspaceAuditPolicy? = nil,
        snapshot: RedactedAuditExportSnapshot? = nil,
        errorMessage: String? = nil,
        blocksPolicyLoad: Bool = false,
        returnsNotConfiguredOnApply: Bool = false
    ) {
        storedPolicy = policy
        self.snapshot = snapshot
        self.errorMessage = errorMessage
        self.blocksPolicyLoad = blocksPolicyLoad
        self.returnsNotConfiguredOnApply = returnsNotConfiguredOnApply
    }

    func replacePolicy(_ policy: ConfirmedWorkspaceAuditPolicy?) {
        storedPolicy = policy
    }

    func policy(for workspaceID: WorkspaceID) async throws -> ConfirmedWorkspaceAuditPolicy? {
        if blocksPolicyLoad { try await Task.sleep(for: .seconds(30)) }
        try throwIfNeeded()
        return storedPolicy
    }

    func confirm(
        _ retention: AuditRetentionPolicy,
        for workspaceID: WorkspaceID,
        confirmedAt: Date
    ) async throws -> ConfirmedWorkspaceAuditPolicy {
        try throwIfNeeded()
        confirmCallCount += 1
        let policy = try ConfirmedWorkspaceAuditPolicy(
            workspaceID: workspaceID,
            revision: (storedPolicy?.revision ?? 0) + 1,
            retention: retention,
            confirmedAt: confirmedAt
        )
        storedPolicy = policy
        return policy
    }

    func applyConfirmedPolicy(
        for workspaceID: WorkspaceID,
        asOf: Date
    ) async throws -> WorkspaceAuditPolicyApplication {
        try throwIfNeeded()
        applyCallCount += 1
        guard !returnsNotConfiguredOnApply, let storedPolicy else { return .notConfigured }
        let result = try AuditRetentionResult(
            workspaceID: workspaceID,
            policy: storedPolicy.retention,
            cutoff: storedPolicy.retention == .indefinite
                ? nil
                : asOf.addingTimeInterval(-30 * 86_400),
            priorRetainedEventCount: 2,
            retainedEventCount: 2,
            prunedEventCount: 0,
            lifetimeEventCount: 2
        )
        let applied = try storedPolicy.recordingApplication(at: asOf)
        self.storedPolicy = applied
        return .applied(result, applied)
    }

    func exportSnapshot(
        _ request: AuditExportRequest,
        generatedAt: Date
    ) async throws -> RedactedAuditExportSnapshot {
        try throwIfNeeded()
        lastExportRequest = request
        guard let snapshot else { throw AuditLifecycleStubError("missing snapshot") }
        return snapshot
    }

    private func throwIfNeeded() throws {
        if let errorMessage { throw AuditLifecycleStubError(errorMessage) }
    }
}

private struct AuditLifecycleStubError: Error, Sendable {
    let value: String
    init(_ value: String) { self.value = value }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

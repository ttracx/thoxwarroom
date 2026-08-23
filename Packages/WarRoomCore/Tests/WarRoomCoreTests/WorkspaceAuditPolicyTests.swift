import Foundation
import XCTest
@testable import WarRoomCore

final class WorkspaceAuditPolicyTests: XCTestCase {
    func testPolicyRequiresExplicitValidRevisionAndDates() throws {
        let workspaceID = fixedWorkspaceID()
        XCTAssertThrowsError(try ConfirmedWorkspaceAuditPolicy(
            workspaceID: workspaceID,
            revision: 0,
            retention: .standard,
            confirmedAt: Date()
        ))
        let applied = try makePolicy(
            revision: 2,
            lastAppliedAt: Date(timeIntervalSince1970: 120)
        )
        XCTAssertThrowsError(try applied.recordingApplication(
            at: Date(timeIntervalSince1970: 119)
        ))
        XCTAssertThrowsError(try ConfirmedWorkspaceAuditPolicy(
            workspaceID: workspaceID,
            revision: 1,
            retention: .standard,
            confirmedAt: Date(timeIntervalSinceReferenceDate: .infinity)
        ))
        XCTAssertThrowsError(try ConfirmedWorkspaceAuditPolicy(
            workspaceID: workspaceID,
            revision: 1,
            retention: .standard,
            confirmedAt: Date(timeIntervalSince1970: 20),
            lastAppliedAt: Date(timeIntervalSince1970: 19)
        ))
    }

    func testPolicyRoundTripIsVersionedAndRevalidates() throws {
        let policy = try makePolicy(revision: 3, lastAppliedAt: Date(timeIntervalSince1970: 120))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        XCTAssertEqual(try decoder.decode(
            ConfirmedWorkspaceAuditPolicy.self,
            from: encoder.encode(policy)
        ), policy)

        let invalid = Data("{\"schemaVersion\":2}".utf8)
        XCTAssertThrowsError(try decoder.decode(ConfirmedWorkspaceAuditPolicy.self, from: invalid))
    }

    func testPolicyCanonicalizesDatesToStableMilliseconds() throws {
        let policy = try ConfirmedWorkspaceAuditPolicy(
            workspaceID: fixedWorkspaceID(),
            revision: 1,
            retention: .standard,
            confirmedAt: Date(timeIntervalSince1970: 100.123_6),
            lastAppliedAt: Date(timeIntervalSince1970: 101.987_6)
        )

        XCTAssertEqual(policy.confirmedAt.timeIntervalSince1970, 100.124, accuracy: 0.000_001)
        let lastAppliedAt = try XCTUnwrap(policy.lastAppliedAt)
        XCTAssertEqual(lastAppliedAt.timeIntervalSince1970, 101.988, accuracy: 0.000_001)
    }

    func testAbsentPolicyNeverInvokesRetention() async throws {
        let store = MemoryPolicyStore()
        let lifecycle = LifecycleSpy()
        let coordinator = WorkspaceAuditLifecycleCoordinator(
            policyStore: store,
            lifecycle: lifecycle
        )

        let result = try await coordinator.applyConfirmedPolicy(
            for: fixedWorkspaceID(),
            asOf: Date(timeIntervalSince1970: 200)
        )

        let callCount = await lifecycle.retentionCallCount
        XCTAssertEqual(result, .notConfigured)
        XCTAssertEqual(callCount, 0)
    }

    func testConfirmThenApplyPersistsSuccessAtNextRevision() async throws {
        let store = MemoryPolicyStore()
        let lifecycle = LifecycleSpy()
        let coordinator = WorkspaceAuditLifecycleCoordinator(
            policyStore: store,
            lifecycle: lifecycle
        )
        let confirmedAt = Date(timeIntervalSince1970: 100)
        let asOf = Date(timeIntervalSince1970: 200)

        let confirmed = try await coordinator.confirm(
            .finite(try AuditRetentionDays(rawValue: 90)),
            for: fixedWorkspaceID(),
            confirmedAt: confirmedAt
        )
        let result = try await coordinator.applyConfirmedPolicy(
            for: fixedWorkspaceID(),
            asOf: asOf
        )

        XCTAssertEqual(confirmed.revision, 1)
        guard case .applied(let retention, let applied) = result else {
            return XCTFail("Expected applied policy")
        }
        XCTAssertEqual(retention.policy, confirmed.retention)
        XCTAssertEqual(applied.revision, 2)
        XCTAssertEqual(applied.lastAppliedAt, asOf)
        let callCount = await lifecycle.retentionCallCount
        let stored = await store.policy(for: fixedWorkspaceID())
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(stored, applied)
    }

    func testRetentionFailureDoesNotRecordApplication() async throws {
        let initial = try makePolicy(revision: 1)
        let store = MemoryPolicyStore(initial: initial)
        let lifecycle = LifecycleSpy(retentionError: TestFailure.expected)
        let coordinator = WorkspaceAuditLifecycleCoordinator(
            policyStore: store,
            lifecycle: lifecycle
        )

        do {
            _ = try await coordinator.applyConfirmedPolicy(
                for: fixedWorkspaceID(),
                asOf: Date(timeIntervalSince1970: 200)
            )
            XCTFail("Expected retention failure")
        } catch {
            XCTAssertEqual(error as? TestFailure, .expected)
        }
        let stored = await store.policy(for: fixedWorkspaceID())
        XCTAssertEqual(stored, initial)
    }

    func testConfirmationCannotBackdateExistingPolicyTimeline() async throws {
        let initial = try makePolicy(
            revision: 2,
            lastAppliedAt: Date(timeIntervalSince1970: 120)
        )
        let store = MemoryPolicyStore(initial: initial)
        let coordinator = WorkspaceAuditLifecycleCoordinator(
            policyStore: store,
            lifecycle: LifecycleSpy()
        )

        await XCTAssertThrowsErrorAsync(try await coordinator.confirm(
            .indefinite,
            for: fixedWorkspaceID(),
            confirmedAt: Date(timeIntervalSince1970: 119)
        )) { error in
            XCTAssertEqual(error as? WorkspaceAuditPolicyError, .invalidPolicy)
        }
        let stored = await store.policy(for: fixedWorkspaceID())
        XCTAssertEqual(stored, initial)
    }

    func testMismatchedLifecycleResultFailsClosedWithoutRecordingApplication() async throws {
        let initial = try makePolicy(revision: 1)
        let store = MemoryPolicyStore(initial: initial)
        let otherWorkspace = WorkspaceID(
            rawValue: UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!
        )
        let lifecycle = LifecycleSpy(resultWorkspaceID: otherWorkspace)
        let coordinator = WorkspaceAuditLifecycleCoordinator(
            policyStore: store,
            lifecycle: lifecycle
        )

        await XCTAssertThrowsErrorAsync(try await coordinator.applyConfirmedPolicy(
            for: fixedWorkspaceID(),
            asOf: Date(timeIntervalSince1970: 200)
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceAuditPolicyError,
                .invalidLifecycleResult
            )
        }
        let stored = await store.policy(for: fixedWorkspaceID())
        XCTAssertEqual(stored, initial)
    }

    func testBackdatedApplicationIsRejectedBeforeRetention() async throws {
        let initial = try makePolicy(
            revision: 2,
            lastAppliedAt: Date(timeIntervalSince1970: 220)
        )
        let lifecycle = LifecycleSpy()
        let coordinator = WorkspaceAuditLifecycleCoordinator(
            policyStore: MemoryPolicyStore(initial: initial),
            lifecycle: lifecycle
        )

        await XCTAssertThrowsErrorAsync(try await coordinator.applyConfirmedPolicy(
            for: fixedWorkspaceID(),
            asOf: Date(timeIntervalSince1970: 219)
        )) { error in
            XCTAssertEqual(error as? WorkspaceAuditPolicyError, .invalidPolicy)
        }
        let callCount = await lifecycle.retentionCallCount
        XCTAssertEqual(callCount, 0)
    }

    func testExportIsDelegatedWithoutCreatingPolicy() async throws {
        let store = MemoryPolicyStore()
        let lifecycle = LifecycleSpy()
        let coordinator = WorkspaceAuditLifecycleCoordinator(
            policyStore: store,
            lifecycle: lifecycle
        )
        let request = try AuditExportRequest(
            workspaceID: fixedWorkspaceID(),
            applicationVersion: "4.2.0"
        )

        _ = try await coordinator.exportSnapshot(
            request,
            generatedAt: Date(timeIntervalSince1970: 300)
        )

        let callCount = await lifecycle.exportCallCount
        let stored = await store.policy(for: fixedWorkspaceID())
        XCTAssertEqual(callCount, 1)
        XCTAssertNil(stored)
    }

    private func makePolicy(
        revision: UInt64,
        lastAppliedAt: Date? = nil
    ) throws -> ConfirmedWorkspaceAuditPolicy {
        try ConfirmedWorkspaceAuditPolicy(
            workspaceID: fixedWorkspaceID(),
            revision: revision,
            retention: .finite(AuditRetentionDays(rawValue: 90)),
            confirmedAt: Date(timeIntervalSince1970: 100),
            lastAppliedAt: lastAppliedAt
        )
    }

    private func fixedWorkspaceID() -> WorkspaceID {
        WorkspaceID(rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!)
    }
}

private actor MemoryPolicyStore: WorkspaceAuditPolicyPersisting {
    private var stored: ConfirmedWorkspaceAuditPolicy?

    init(initial: ConfirmedWorkspaceAuditPolicy? = nil) { stored = initial }

    func policy(for workspaceID: WorkspaceID) -> ConfirmedWorkspaceAuditPolicy? {
        stored?.workspaceID == workspaceID ? stored : nil
    }

    func save(
        _ policy: ConfirmedWorkspaceAuditPolicy,
        replacingRevision: UInt64?
    ) throws {
        guard stored?.revision == replacingRevision else { throw TestFailure.conflict }
        stored = policy
    }
}

private actor LifecycleSpy: AuditLifecycleManaging {
    private(set) var retentionCallCount = 0
    private(set) var exportCallCount = 0
    private let retentionError: Error?
    private let resultWorkspaceID: WorkspaceID?

    init(
        retentionError: Error? = nil,
        resultWorkspaceID: WorkspaceID? = nil
    ) {
        self.retentionError = retentionError
        self.resultWorkspaceID = resultWorkspaceID
    }

    func applyRetention(
        _ policy: AuditRetentionPolicy,
        to workspaceID: WorkspaceID,
        asOf: Date
    ) throws -> AuditRetentionResult {
        retentionCallCount += 1
        if let retentionError { throw retentionError }
        return try AuditRetentionResult(
            workspaceID: resultWorkspaceID ?? workspaceID,
            policy: policy,
            cutoff: policy == .indefinite ? nil : asOf.addingTimeInterval(-30 * 86_400),
            priorRetainedEventCount: 0,
            retainedEventCount: 0,
            prunedEventCount: 0,
            lifetimeEventCount: 0
        )
    }

    func exportSnapshot(
        _ request: AuditExportRequest,
        generatedAt: Date
    ) throws -> RedactedAuditExportSnapshot {
        exportCallCount += 1
        let integrity = try AuditExportIntegrity(
            ledgerGeneration: 0,
            retainedEventCount: 0,
            lifetimeEventCount: 0,
            sourceHeadSHA256: String(repeating: "0", count: 64),
            snapshotSHA256: String(repeating: "1", count: 64)
        )
        return try RedactedAuditExportSnapshot(
            generatedAt: generatedAt,
            workspaceID: request.workspaceID,
            occurredOnOrAfter: request.occurredOnOrAfter,
            occurredBefore: request.occurredBefore,
            applicationVersion: request.applicationVersion,
            events: [],
            truncated: false,
            integrity: integrity
        )
    }
}

private enum TestFailure: Error, Equatable { case expected, conflict }

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

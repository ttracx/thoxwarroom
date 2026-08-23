import XCTest
import WarRoomCore
@testable import ThoxWarRoom

@MainActor
final class HermesOperationReconciliationModelTests: XCTestCase {
    func testLoadReadsBoundedPendingAndTerminalEvidenceForExactWorkspace() async throws {
        let pendingRecord = try makeRecord(status: .pending, correlationSeed: 1)
        let terminalRecord = try makeRecord(status: .terminal, correlationSeed: 2)
        let reader = ReconciliationReaderStub(pages: [
            try makePage(status: .pending, records: [pendingRecord], truncated: true),
            try makePage(status: .terminal, records: [terminalRecord]),
        ])
        let model = makeModel(reader: reader)

        model.load()
        await model.waitForCurrentLoad()

        guard case .loaded(let snapshot) = model.phase else {
            return XCTFail("Expected loaded reconciliation evidence")
        }
        XCTAssertEqual(snapshot.workspaceID, workspaceID)
        XCTAssertEqual(snapshot.pending.records, [pendingRecord])
        XCTAssertTrue(snapshot.pending.truncated)
        XCTAssertEqual(snapshot.terminal.records, [terminalRecord])
        let queries = await reader.capturedQueries
        XCTAssertEqual(queries.map(\.workspaceID), [workspaceID, workspaceID])
        XCTAssertEqual(queries.map(\.status), [.pending, .terminal])
        XCTAssertEqual(queries.map(\.limit), [.standard, .standard])
    }

    func testUnavailableReaderFailsClosedWithoutStartingARead() {
        let model = makeModel(reader: nil)

        XCTAssertFalse(model.canLoad)
        model.load()

        XCTAssertEqual(
            model.phase,
            .unavailable("Encrypted operation evidence is unavailable on this device.")
        )
    }

    func testStorageFailureIsCollapsedToBoundedRedactedMessage() async {
        let unsafe = "/Users/person/private/audit-token-secret"
        let model = makeModel(reader: ReconciliationReaderStub(errorMessage: unsafe))

        model.load()
        await model.waitForCurrentLoad()

        guard case .failed(let message) = model.phase else {
            return XCTFail("Expected a safe failure")
        }
        XCTAssertEqual(
            message,
            "Encrypted operation evidence could not be verified. No Hermes action was taken."
        )
        XCTAssertFalse(message.contains(unsafe))
        XCTAssertLessThan(message.utf8.count, 160)
    }

    func testCrossWorkspacePageIsRejectedRatherThanDisplayed() async throws {
        let otherWorkspace = WorkspaceID(
            rawValue: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        )
        let reader = ReconciliationReaderStub(pages: [
            try AuditedOperationReconciliationPage(
                workspaceID: otherWorkspace,
                status: .pending,
                records: [],
                truncated: false
            ),
            try makePage(status: .terminal, records: []),
        ])
        let model = makeModel(reader: reader)

        model.load()
        await model.waitForCurrentLoad()

        guard case .failed = model.phase else {
            return XCTFail("Mismatched workspace provenance must fail closed")
        }
    }

    func testCancellationStopsReadAndAllowsDeliberateReload() async {
        let reader = ReconciliationReaderStub(blockUntilCancelled: true)
        let model = makeModel(reader: reader)

        model.load()
        await Task.yield()
        model.cancelLoading()
        await model.waitForCurrentLoad()

        XCTAssertEqual(model.phase, .cancelled)
        XCTAssertTrue(model.canLoad)
        let queries = await reader.capturedQueries
        XCTAssertEqual(queries.count, 1)
    }

    private let workspaceID = WorkspaceID(
        rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    )

    private func makeModel(
        reader: (any HermesOperationReconciliationReading)?
    ) -> HermesOperationReconciliationModel {
        HermesOperationReconciliationModel(
            workspaceID: workspaceID,
            workspaceName: "Research workspace",
            reader: reader
        )
    }

    private func makePage(
        status: AuditedOperationReconciliationStatus,
        records: [AuditedOperationReconciliationRecord],
        truncated: Bool = false
    ) throws -> AuditedOperationReconciliationPage {
        try AuditedOperationReconciliationPage(
            workspaceID: workspaceID,
            status: status,
            records: records,
            truncated: truncated
        )
    }

    private func makeRecord(
        status: AuditedOperationReconciliationStatus,
        correlationSeed: UInt8
    ) throws -> AuditedOperationReconciliationRecord {
        let correlationID = AuditedOperationCorrelationID(rawValue: UUID(uuid: (
            correlationSeed, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, correlationSeed, 0, 0, 0, correlationSeed
        )))
        let fields = [
            AuditField(
                key: "correlation_id",
                value: .string(correlationID.description),
                privacy: .nonSensitive
            ),
            AuditField(key: "operation", value: .string("approval"), privacy: .nonSensitive),
            AuditField(key: "choice", value: .string("deny"), privacy: .nonSensitive),
        ]
        let intent = try PersistableAuditEvent(event: AuditEvent(
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            workspaceID: workspaceID,
            category: "hermes.operation",
            action: "intent",
            outcome: .requested,
            fields: fields
        ))
        let outcome: PersistableAuditEvent? = status == .terminal
            ? try PersistableAuditEvent(event: AuditEvent(
                occurredAt: Date(timeIntervalSince1970: 1_700_000_001),
                workspaceID: workspaceID,
                category: "hermes.operation",
                action: "outcome",
                outcome: .denied,
                fields: fields
            ))
            : nil
        return try AuditedOperationReconciliationRecord(
            workspaceID: workspaceID,
            correlationID: correlationID,
            intent: intent,
            outcome: outcome
        )
    }
}

private actor ReconciliationReaderStub: HermesOperationReconciliationReading {
    private(set) var capturedQueries: [AuditedOperationReconciliationQuery] = []
    let pages: [AuditedOperationReconciliationPage]
    let errorMessage: String?
    let blockUntilCancelled: Bool

    init(
        pages: [AuditedOperationReconciliationPage] = [],
        errorMessage: String? = nil,
        blockUntilCancelled: Bool = false
    ) {
        self.pages = pages
        self.errorMessage = errorMessage
        self.blockUntilCancelled = blockUntilCancelled
    }

    func reconciliationRecords(
        matching query: AuditedOperationReconciliationQuery
    ) async throws -> AuditedOperationReconciliationPage {
        capturedQueries.append(query)
        if blockUntilCancelled {
            try await Task.sleep(for: .seconds(30))
        }
        if let errorMessage { throw UnsafeReaderError(errorMessage) }
        if let page = pages.first(where: { $0.status == query.status }) { return page }
        return try AuditedOperationReconciliationPage(
            workspaceID: query.workspaceID,
            status: query.status,
            records: [],
            truncated: false
        )
    }
}

private struct UnsafeReaderError: Error, Sendable {
    let value: String
    init(_ value: String) { self.value = value }
}

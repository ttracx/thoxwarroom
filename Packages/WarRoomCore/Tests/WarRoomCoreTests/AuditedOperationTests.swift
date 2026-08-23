import Foundation
import XCTest
@testable import WarRoomCore

final class AuditedOperationTests: XCTestCase {
    func testCorrelationIDIsExplicitStableAndCodable() throws {
        let value = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let correlationID = AuditedOperationCorrelationID(rawValue: value)

        let encoded = try JSONEncoder().encode(correlationID)
        let decoded = try JSONDecoder().decode(AuditedOperationCorrelationID.self, from: encoded)

        XCTAssertEqual(decoded, correlationID)
        XCTAssertEqual(correlationID.description, value.uuidString.lowercased())
    }

    func testRequestedIsARepresentableAuditOutcome() throws {
        let encoded = try JSONEncoder().encode(AuditOutcome.requested)

        XCTAssertEqual(try JSONDecoder().decode(AuditOutcome.self, from: encoded), .requested)
    }

    func testReconciliationLimitRejectsUnboundedValues() throws {
        XCTAssertThrowsError(try AuditedOperationReconciliationLimit(rawValue: 0)) {
            XCTAssertEqual(
                $0 as? AuditedOperationPersistenceError,
                .invalidReconciliationLimit(0)
            )
        }
        XCTAssertThrowsError(try AuditedOperationReconciliationLimit(rawValue: 501)) {
            XCTAssertEqual(
                $0 as? AuditedOperationPersistenceError,
                .invalidReconciliationLimit(501)
            )
        }
        XCTAssertEqual(
            try AuditedOperationReconciliationLimit(rawValue: 500).rawValue,
            500
        )
    }

    func testReconciliationRecordRequiresWorkspaceAndCorrelationEvidence() throws {
        let first = WorkspaceID(rawValue: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
        let second = WorkspaceID(rawValue: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!)
        let correlation = AuditedOperationCorrelationID(
            rawValue: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        )
        let validIntent = try operationEvent(
            workspaceID: first,
            correlation: correlation,
            action: "intent"
        )
        let validOutcome = try operationEvent(
            workspaceID: first,
            correlation: correlation,
            action: "outcome"
        )

        let pending = try AuditedOperationReconciliationRecord(
            workspaceID: first,
            correlationID: correlation,
            intent: validIntent,
            outcome: nil
        )
        XCTAssertEqual(pending.status, .pending)
        XCTAssertEqual(
            try AuditedOperationReconciliationRecord(
                workspaceID: first,
                correlationID: correlation,
                intent: validIntent,
                outcome: validOutcome
            ).status,
            .terminal
        )

        let crossWorkspace = try operationEvent(
            workspaceID: second,
            correlation: correlation,
            action: "outcome"
        )
        XCTAssertThrowsError(try AuditedOperationReconciliationRecord(
            workspaceID: first,
            correlationID: correlation,
            intent: validIntent,
            outcome: crossWorkspace
        )) {
            XCTAssertEqual($0 as? AuditedOperationPersistenceError, .crossWorkspaceRecord)
        }

        let otherCorrelation = AuditedOperationCorrelationID(rawValue: UUID())
        let mismatched = try operationEvent(
            workspaceID: first,
            correlation: otherCorrelation,
            action: "intent"
        )
        XCTAssertThrowsError(try AuditedOperationReconciliationRecord(
            workspaceID: first,
            correlationID: correlation,
            intent: mismatched,
            outcome: nil
        )) {
            XCTAssertEqual($0 as? AuditedOperationPersistenceError, .invalidCorrelationEvidence)
        }
    }

    func testReconciliationPageRejectsWrongStatus() throws {
        let workspaceID = WorkspaceID.make()
        let correlation = AuditedOperationCorrelationID(rawValue: UUID())
        let pending = try AuditedOperationReconciliationRecord(
            workspaceID: workspaceID,
            correlationID: correlation,
            intent: operationEvent(
                workspaceID: workspaceID,
                correlation: correlation,
                action: "intent"
            ),
            outcome: nil
        )

        XCTAssertThrowsError(try AuditedOperationReconciliationPage(
            workspaceID: workspaceID,
            status: .terminal,
            records: [pending],
            truncated: false
        )) {
            XCTAssertEqual($0 as? AuditedOperationPersistenceError, .invalidReconciliationPage)
        }
    }

    private func operationEvent(
        workspaceID: WorkspaceID,
        correlation: AuditedOperationCorrelationID,
        action: String
    ) throws -> PersistableAuditEvent {
        try PersistableAuditEvent(event: AuditEvent(
            workspaceID: workspaceID,
            category: "hermes.operation",
            action: action,
            outcome: action == "intent" ? .requested : .succeeded,
            fields: [
                AuditField(
                    key: "correlation_id",
                    value: .string(correlation.description),
                    privacy: .nonSensitive
                ),
            ]
        ))
    }
}

import Foundation
import XCTest
@testable import WarRoomCore

final class DurableAuditPersistenceTests: XCTestCase {
    func testPersistableAuditEventAndCursorRoundTripWithRedactedValues() throws {
        let secret = "must-not-persist"
        let event = AuditEvent(
            workspaceID: .make(),
            category: "workspace",
            action: "unlock",
            outcome: .denied,
            fields: [
                AuditField(key: "credential", value: .string(secret), privacy: .nonSensitive),
                AuditField(key: "boundary", value: .string("localMachine"), privacy: .nonSensitive),
            ]
        )
        let record = try PersistableAuditEvent(event: event)
        let cursor = try AuditEventCursor(value: Data("opaque-position".utf8))

        let encodedRecord = try JSONEncoder().encode(record)
        XCTAssertFalse(String(decoding: encodedRecord, as: UTF8.self).contains(secret))
        XCTAssertEqual(try JSONDecoder().decode(PersistableAuditEvent.self, from: encodedRecord), record)
        XCTAssertEqual(
            try JSONDecoder().decode(AuditEventCursor.self, from: JSONEncoder().encode(cursor)),
            cursor
        )
        XCTAssertEqual(cursor.description, "<redacted-audit-cursor>")
        XCTAssertFalse(String(describing: cursor).contains("opaque-position"))
    }

    func testCursorProvidesScopedBytesWhileKeepingDescriptionsRedacted() throws {
        let bytes = Data("store-owned-continuation".utf8)
        let cursor = try AuditEventCursor(value: bytes)

        let recovered = cursor.withUnsafeBytes { Data($0) }

        XCTAssertEqual(recovered, bytes)
        XCTAssertEqual(cursor.description, "<redacted-audit-cursor>")
        XCTAssertEqual(cursor.debugDescription, "AuditEventCursor(<redacted>)")
        XCTAssertFalse(String(describing: cursor).contains("store-owned-continuation"))
    }

    func testDecodedInputCannotBypassRedactionValidation() throws {
        let safe = AuditEvent(
            workspaceID: .make(),
            category: "provider",
            action: "connect",
            outcome: .failed
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(safe)) as? [String: Any]
        )
        object["metadata"] = [
            "prompt": ["type": "string", "string": "private prompt"],
        ]
        let decoded = try JSONDecoder().decode(
            AuditEvent.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.metadata["prompt"], .redacted)
        let persistable = try PersistableAuditEvent(event: decoded)
        let reencoded = try JSONEncoder().encode(persistable)
        XCTAssertFalse(String(decoding: reencoded, as: UTF8.self).contains("private prompt"))
    }

    func testRejectsInvalidNamesMetadataCursorPageAndTimeBounds() throws {
        let workspaceID = WorkspaceID.make()
        let invalidName = AuditEvent(
            workspaceID: workspaceID,
            category: "",
            action: "connect",
            outcome: .failed
        )
        XCTAssertThrowsError(try PersistableAuditEvent(event: invalidName)) { error in
            XCTAssertEqual(error as? AuditPersistenceError, .invalidEventName)
        }

        let oversizedMetadata = AuditEvent(
            workspaceID: workspaceID,
            category: "provider",
            action: "connect",
            outcome: .succeeded,
            fields: [AuditField(
                key: "summary",
                value: .string(String(repeating: "🛡️", count: 256)),
                privacy: .nonSensitive
            )]
        )
        XCTAssertThrowsError(try PersistableAuditEvent(event: oversizedMetadata)) { error in
            XCTAssertEqual(error as? AuditPersistenceError, .metadataTooLarge)
        }

        XCTAssertThrowsError(try AuditEventCursor(value: Data()))
        XCTAssertThrowsError(try AuditEventCursor(
            value: Data(repeating: 1, count: AuditEventCursor.maximumBytes + 1)
        ))
        for limit in [0, AuditEventPageLimit.maximum + 1] {
            XCTAssertThrowsError(try AuditEventPageLimit(rawValue: limit)) { error in
                XCTAssertEqual(error as? AuditPersistenceError, .invalidPageLimit(limit))
            }
        }
        let date = Date(timeIntervalSince1970: 100)
        XCTAssertThrowsError(try AuditEventQuery(
            workspaceID: workspaceID,
            occurredOnOrAfter: date,
            occurredBefore: date
        )) { error in
            XCTAssertEqual(error as? AuditPersistenceError, .invalidTimeRange)
        }
    }

    func testPageRejectsCrossWorkspaceEventsAndExcessCount() throws {
        let firstWorkspace = WorkspaceID.make()
        let secondWorkspace = WorkspaceID.make()
        let foreign = try record(workspaceID: secondWorkspace, occurredAt: Date())
        XCTAssertThrowsError(try AuditEventPage(
            workspaceID: firstWorkspace,
            events: [foreign]
        )) { error in
            XCTAssertEqual(error as? AuditPersistenceError, .crossWorkspaceEvent)
        }

        let event = try record(workspaceID: firstWorkspace, occurredAt: Date())
        XCTAssertThrowsError(try AuditEventPage(
            workspaceID: firstWorkspace,
            events: Array(repeating: event, count: AuditEventPageLimit.maximum + 1)
        )) { error in
            XCTAssertEqual(error as? AuditPersistenceError, .pageTooLarge)
        }
    }

    func testOfflineDurableStoreReturnsOnlyRequestedWorkspaceAndTimeRange() async throws {
        let firstWorkspace = WorkspaceID.make()
        let secondWorkspace = WorkspaceID.make()
        let start = Date(timeIntervalSince1970: 100)
        let first = try record(workspaceID: firstWorkspace, occurredAt: start)
        let second = try record(workspaceID: firstWorkspace, occurredAt: start.addingTimeInterval(10))
        let foreign = try record(workspaceID: secondWorkspace, occurredAt: start.addingTimeInterval(5))
        let store: any DurableAuditEventStore = IsolatedAuditEventStore()
        try await store.append(first)
        try await store.append(second)
        try await store.append(foreign)

        let query = try AuditEventQuery(
            workspaceID: firstWorkspace,
            occurredOnOrAfter: start.addingTimeInterval(5),
            occurredBefore: start.addingTimeInterval(20),
            limit: try AuditEventPageLimit(rawValue: 10)
        )
        let page = try await store.events(matching: query)

        XCTAssertEqual(page.workspaceID, firstWorkspace)
        XCTAssertEqual(page.events, [second])
        XCTAssertTrue(page.events.allSatisfy { $0.event.workspaceID == firstWorkspace })
        XCTAssertNil(page.nextCursor)
    }

    private func record(
        workspaceID: WorkspaceID,
        occurredAt: Date
    ) throws -> PersistableAuditEvent {
        try PersistableAuditEvent(event: AuditEvent(
            occurredAt: occurredAt,
            workspaceID: workspaceID,
            category: "workspace",
            action: "read",
            outcome: .succeeded,
            fields: [AuditField(
                key: "boundary",
                value: .string("localMachine"),
                privacy: .nonSensitive
            )]
        ))
    }
}

private actor IsolatedAuditEventStore: DurableAuditEventStore {
    private var values: [WorkspaceID: [PersistableAuditEvent]] = [:]

    func append(_ event: PersistableAuditEvent) {
        values[event.event.workspaceID, default: []].append(event)
    }

    func events(matching query: AuditEventQuery) throws -> AuditEventPage {
        let matching = values[query.workspaceID, default: []]
            .filter { record in
                if let lower = query.occurredOnOrAfter,
                   record.event.occurredAt < lower { return false }
                if let upper = query.occurredBefore,
                   record.event.occurredAt >= upper { return false }
                return true
            }
            .sorted { $0.event.occurredAt < $1.event.occurredAt }
        return try AuditEventPage(
            workspaceID: query.workspaceID,
            events: Array(matching.prefix(query.limit.rawValue))
        )
    }
}

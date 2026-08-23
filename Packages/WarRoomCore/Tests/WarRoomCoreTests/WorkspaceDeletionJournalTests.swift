import Foundation
import XCTest
@testable import WarRoomCore

final class WorkspaceDeletionJournalTests: XCTestCase {
    func testEntryRoundTripsWithVersionAndRedactedDescription() throws {
        let workspaceID = WorkspaceID(
            rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        )
        let entry = WorkspaceDeletionJournalEntry(
            workspaceID: workspaceID,
            stage: .encryptedWorkspaceDeletionPending
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(WorkspaceDeletionJournalEntry.self, from: data)

        XCTAssertEqual(decoded, entry)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("\"schemaVersion\":1") == true)
        XCTAssertFalse(String(describing: entry).contains(workspaceID.rawValue.uuidString))
        XCTAssertTrue(String(describing: entry).contains("<redacted>"))
    }

    func testRejectsUnsupportedSchema() {
        let data = Data(
            """
            {"schemaVersion":2,"workspaceID":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","stage":"credentialDeletionPending"}
            """.utf8
        )

        XCTAssertThrowsError(
            try JSONDecoder().decode(WorkspaceDeletionJournalEntry.self, from: data)
        )
    }
}

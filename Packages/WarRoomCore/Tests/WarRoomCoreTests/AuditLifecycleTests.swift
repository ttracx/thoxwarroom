import Foundation
import XCTest
@testable import WarRoomCore

final class AuditLifecycleTests: XCTestCase {
    func testRetentionPolicyHasExplicitBoundedDaysDefaultAndIndefiniteChoice() throws {
        XCTAssertEqual(AuditRetentionPolicy.standard, .finite(try AuditRetentionDays(rawValue: 365)))
        XCTAssertEqual(try AuditRetentionDays(rawValue: 30).rawValue, 30)
        XCTAssertEqual(try AuditRetentionDays(rawValue: 2_555).rawValue, 2_555)
        XCTAssertThrowsError(try AuditRetentionDays(rawValue: 29))
        XCTAssertThrowsError(try AuditRetentionDays(rawValue: 2_556))
        XCTAssertEqual(AuditRetentionPolicy.indefinite, .indefinite)
        XCTAssertThrowsError(try JSONDecoder().decode(
            AuditRetentionDays.self,
            from: Data("29".utf8)
        ))
    }

    func testExportRequestRejectsUnboundedRangeAndPathLikeApplicationVersion() throws {
        let workspaceID = WorkspaceID(rawValue: UUID())
        XCTAssertThrowsError(try AuditExportLimit(rawValue: 0))
        XCTAssertThrowsError(try AuditExportLimit(rawValue: AuditExportLimit.maximum + 1))
        XCTAssertThrowsError(try AuditExportRequest(
            workspaceID: workspaceID,
            occurredOnOrAfter: Date(timeIntervalSince1970: 2),
            occurredBefore: Date(timeIntervalSince1970: 1),
            applicationVersion: "1.0"
        ))
        XCTAssertThrowsError(try AuditExportRequest(
            workspaceID: workspaceID,
            applicationVersion: "/private/build/1.0"
        ))
    }
}

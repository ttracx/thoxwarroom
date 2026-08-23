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
}

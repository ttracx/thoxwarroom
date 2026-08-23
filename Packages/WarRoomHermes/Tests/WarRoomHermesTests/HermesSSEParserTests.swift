import Foundation
import XCTest
@testable import WarRoomHermes

final class HermesSSEParserTests: XCTestCase {
    func testParsesFragmentedSSEAndIgnoresComments() throws {
        let fixture = try fixtureData("events-fragmented", extension: "sse")
        var parser = HermesSSEParser()
        var events: [HermesRunEvent] = []

        for byte in fixture {
            events.append(contentsOf: try parser.append(Data([byte])))
        }
        events.append(contentsOf: try parser.finish())

        XCTAssertEqual(events.count, 4)
        guard case .messageDelta(let delta) = events[0] else {
            return XCTFail("Expected message delta")
        }
        XCTAssertEqual(delta.delta, "hello")
        guard case .toolStarted(let tool) = events[1] else {
            return XCTFail("Expected tool started")
        }
        XCTAssertEqual(tool.toolName, "search")
        guard case .approvalRequest(let approval) = events[2] else {
            return XCTFail("Expected approval request")
        }
        XCTAssertEqual(approval.choices, HermesApprovalChoice.allCases)
        guard case .runCompleted = events[3] else {
            return XCTFail("Expected completed event")
        }
    }

    func testUnknownEventsDiscardPayloadAndRedactUnsafeName() throws {
        var parser = HermesSSEParser()
        var events = try parser.append(try fixtureData("events-unknown", extension: "sse"))
        events.append(contentsOf: try parser.finish())

        XCTAssertEqual(
            events,
            [
                .unknown(HermesUnknownEvent(auditName: "future.safe_event", payloadWasDiscarded: true)),
                .unknown(HermesUnknownEvent(auditName: "<redacted>", payloadWasDiscarded: true)),
            ]
        )
        XCTAssertFalse(String(describing: events).contains("discard-me"))
        XCTAssertFalse(String(describing: events).contains("must-not-survive"))
    }

    func testMalformedPayloadFailsButNextRecordCanBeParsed() throws {
        var parser = HermesSSEParser()
        var malformed = try fixtureData("events-malformed", extension: "sse")
        malformed.append(contentsOf: Data("\n".utf8))
        XCTAssertThrowsError(
            try parser.append(malformed)
        ) { error in
            XCTAssertEqual(error as? HermesSSEError, .malformedJSON)
        }

        let recovered = try parser.append(
            Data("data: {\"event\":\"run.cancelled\",\"run_id\":\"next\"}\n\n".utf8)
        )
        XCTAssertEqual(recovered.count, 1)
        guard case .runCancelled = recovered[0] else {
            return XCTFail("Expected parser recovery")
        }
    }

    func testRejectsNonCanonicalApprovalChoices() {
        var parser = HermesSSEParser()
        let data = Data(
            "data: {\"event\":\"approval.request\",\"run_id\":\"opaque\",\"choices\":[\"approve\",\"deny\"]}\n\n".utf8
        )
        XCTAssertThrowsError(try parser.append(data)) { error in
            XCTAssertEqual(error as? HermesSSEError, .invalidApprovalChoices)
        }
    }

    func testEnforcesBufferAndEventBounds() throws {
        var bufferLimited = try HermesSSEParser(maximumBufferedBytes: 8, maximumEventBytes: 8)
        XCTAssertThrowsError(try bufferLimited.append(Data(repeating: 65, count: 9))) { error in
            XCTAssertEqual(error as? HermesSSEError, .bufferLimitExceeded)
        }

        var eventLimited = try HermesSSEParser(maximumBufferedBytes: 128, maximumEventBytes: 7)
        XCTAssertThrowsError(try eventLimited.append(Data("data: {}\n\n".utf8))) { error in
            XCTAssertEqual(error as? HermesSSEError, .eventLimitExceeded)
        }
    }

    func testRejectsInvalidLimitsWithoutArithmeticOverflow() {
        XCTAssertThrowsError(try HermesSSEParser(maximumBufferedBytes: -1, maximumEventBytes: 1)) {
            XCTAssertEqual($0 as? HermesLimitError, .invalidSSELimits)
        }
        XCTAssertThrowsError(
            try HermesSSEParser(maximumBufferedBytes: Int.max, maximumEventBytes: Int.max)
        ) {
            XCTAssertEqual($0 as? HermesLimitError, .invalidSSELimits)
        }
        XCTAssertThrowsError(try HermesSSEParser(maximumBufferedBytes: 8, maximumEventBytes: 9)) {
            XCTAssertEqual($0 as? HermesLimitError, .invalidSSELimits)
        }
    }

    private func fixtureData(_ name: String, extension fileExtension: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: fileExtension))
        return try Data(contentsOf: url)
    }
}

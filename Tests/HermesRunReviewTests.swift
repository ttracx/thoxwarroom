import Foundation
import XCTest
import WarRoomHermes
@testable import ThoxWarRoom

@MainActor
final class HermesRunReviewModelTests: XCTestCase {
    func testEmptyIdentifierDoesNotCallService() async {
        let service = HermesRunReviewServiceStub(mode: .success(events: []))
        let model = HermesRunReviewModel(service: service)

        model.startLoading()
        await model.waitForCurrentLoad()

        XCTAssertEqual(model.phase, .failed("Enter a valid opaque run identifier."))
        let callCount = await service.callCount
        XCTAssertEqual(callCount, 0)
    }

    func testLoadsStatusAndBufferedEventsWithoutExposingRunID() async throws {
        let runID = try XCTUnwrap(HermesRunID(rawValue: "sensitive-opaque-value"))
        var parser = HermesSSEParser()
        let unknownEvents = try parser.append(
            Data("data: {\"event\":\"future.safe\",\"secret\":\"discarded\"}\n\n".utf8)
        )
        let unknownEvent = try XCTUnwrap(unknownEvents.first)
        let events: [HermesRunEvent] = [
            .runCompleted(HermesEventMetadata(runID: runID, timestamp: "2026-08-23T12:00:00Z")),
            unknownEvent,
        ]
        let service = HermesRunReviewServiceStub(mode: .success(events: events))
        let model = HermesRunReviewModel(service: service)
        model.runIDInput = runID.rawValue

        model.startLoading()
        await model.waitForCurrentLoad()

        XCTAssertEqual(
            model.phase,
            .loaded(HermesRunReviewSnapshot(status: .running, events: events))
        )
        let callCount = await service.callCount
        XCTAssertEqual(callCount, 1)
        XCTAssertFalse(String(describing: model.phase).contains(runID.rawValue))
    }

    func testSuccessfulRunWithNoEventsKeepsExplicitEmptySnapshot() async throws {
        let runID = try XCTUnwrap(HermesRunID(rawValue: "opaque-empty-events"))
        let model = HermesRunReviewModel(
            service: HermesRunReviewServiceStub(mode: .success(events: []))
        )
        model.runIDInput = runID.rawValue

        model.startLoading()
        await model.waitForCurrentLoad()

        XCTAssertEqual(
            model.phase,
            .loaded(HermesRunReviewSnapshot(status: .running, events: []))
        )
    }

    func testServiceErrorIsSanitizedAndRetrySucceeds() async throws {
        let runID = try XCTUnwrap(HermesRunID(rawValue: "must-not-appear-in-error"))
        let service = HermesRunReviewServiceStub(mode: .failure)
        let model = HermesRunReviewModel(service: service)
        model.runIDInput = runID.rawValue

        model.startLoading()
        await model.waitForCurrentLoad()

        guard case .failed(let message) = model.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertFalse(message.contains(runID.rawValue))
        XCTAssertEqual(
            message,
            "Unable to load this Hermes run. No run identifier was included in this error."
        )

        await service.setMode(.success(events: []))
        model.retry()
        await model.waitForCurrentLoad()
        XCTAssertEqual(
            model.phase,
            .loaded(HermesRunReviewSnapshot(status: .running, events: []))
        )
    }

    func testCancellationCannotBeOverwrittenByLateResults() async throws {
        let runID = try XCTUnwrap(HermesRunID(rawValue: "opaque-cancel"))
        let service = HermesRunReviewServiceStub(mode: .delayed)
        let model = HermesRunReviewModel(service: service)
        model.runIDInput = runID.rawValue

        model.startLoading()
        await Task.yield()
        model.cancelLoading()
        await model.waitForCurrentLoad()

        XCTAssertEqual(model.phase, .cancelled)
    }

    func testOlderCancelledLoadCannotOverwriteNewerResult() async throws {
        let firstRunID = try XCTUnwrap(HermesRunID(rawValue: "opaque-first"))
        let secondRunID = try XCTUnwrap(HermesRunID(rawValue: "opaque-second"))
        let service = HermesRunReviewServiceStub(mode: .delayedIgnoringCancellation)
        let model = HermesRunReviewModel(service: service)
        model.runIDInput = firstRunID.rawValue

        model.startLoading()
        for _ in 0..<100 {
            if await service.callCount == 1 { break }
            await Task.yield()
        }
        let firstLoadCallCount = await service.callCount
        XCTAssertEqual(firstLoadCallCount, 1)
        await service.setMode(.success(events: []))
        model.runIDInput = secondRunID.rawValue
        model.startLoading()
        await model.waitForCurrentLoad()

        XCTAssertEqual(
            model.phase,
            .loaded(HermesRunReviewSnapshot(status: .running, events: []))
        )
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(
            model.phase,
            .loaded(HermesRunReviewSnapshot(status: .running, events: []))
        )
    }

    func testRecentRunPickerUsesOpaqueSelectionWithoutDisplayContract() throws {
        let runID = try XCTUnwrap(HermesRunID(rawValue: "opaque-recent"))
        let model = HermesRunReviewModel(
            service: HermesRunReviewServiceStub(mode: .success(events: [])),
            recentRuns: [runID]
        )

        model.selectRecentRun(runID)

        XCTAssertEqual(model.selectedRecentRun, runID)
        XCTAssertEqual(model.runIDInput, runID.rawValue)
        XCTAssertEqual(model.recentRuns.count, 1)
    }
}

private actor HermesRunReviewServiceStub: HermesRunReviewServicing {
    enum Mode: Sendable {
        case success(events: [HermesRunEvent])
        case failure
        case delayed
        case delayedIgnoringCancellation
    }

    private var mode: Mode
    private(set) var callCount = 0

    init(mode: Mode) {
        self.mode = mode
    }

    func setMode(_ mode: Mode) {
        self.mode = mode
    }

    func loadSnapshot(for runID: HermesRunID) async throws -> HermesRunReviewSnapshot {
        callCount += 1
        switch mode {
        case .success(let events):
            return HermesRunReviewSnapshot(status: .running, events: events)
        case .failure:
            throw HermesRunReviewTestError.service("failed for \(runID.rawValue)")
        case .delayed:
            try await Task.sleep(for: .seconds(30))
            return HermesRunReviewSnapshot(status: .running, events: [])
        case .delayedIgnoringCancellation:
            try? await Task.sleep(for: .milliseconds(100))
            return HermesRunReviewSnapshot(status: .running, events: [])
        }
    }
}

private enum HermesRunReviewTestError: Error {
    case service(String)
}

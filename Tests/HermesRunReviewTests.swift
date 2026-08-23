import Foundation
import XCTest
import WarRoomHermes
@testable import ThoxWarRoom

@MainActor
final class HermesRunReviewModelTests: XCTestCase {
    func testEmptyIdentifierDoesNotCallService() async {
        let service = HermesRunReviewServiceStub(mode: .finished(events: []))
        let model = HermesRunReviewModel(service: service)

        model.startLoading()
        await model.waitForCurrentLoad()

        XCTAssertEqual(
            model.phase,
            .failed("Enter a valid opaque run identifier.", partialSnapshot: nil)
        )
        let callCount = await service.callCount
        XCTAssertEqual(callCount, 0)
    }

    func testPublishesIncrementalEventBeforeStreamFinishes() async throws {
        let runID = try XCTUnwrap(HermesRunID(rawValue: "sensitive-opaque-value"))
        let event = HermesRunEvent.reasoningAvailable(
            HermesEventMetadata(runID: runID, timestamp: "2026-08-23T12:00:00Z")
        )
        let service = HermesRunReviewServiceStub(mode: .pending(events: [event]))
        let model = HermesRunReviewModel(service: service)
        model.runIDInput = runID.rawValue

        model.startLoading()
        await eventually {
            model.phase == HermesRunReviewModel.Phase.live(
                HermesRunReviewSnapshot(status: .running, events: [event])
            )
        }

        XCTAssertEqual(
            model.phase,
            HermesRunReviewModel.Phase.live(
                HermesRunReviewSnapshot(status: .running, events: [event])
            )
        )
        XCTAssertFalse(String(describing: model.phase).contains(runID.rawValue))
        model.cancelLoading()
        await model.waitForCurrentLoad()
        await eventually { await service.streamTerminationCount == 1 }
        let terminationCount = await service.currentStreamTerminationCount()
        XCTAssertEqual(terminationCount, 1)
    }

    func testTerminalEventCompletesReviewAndUpdatesStatus() async throws {
        let runID = try XCTUnwrap(HermesRunID(rawValue: "opaque-complete"))
        let event = HermesRunEvent.runCompleted(
            HermesEventMetadata(runID: runID, timestamp: "2026-08-23T12:00:00Z")
        )
        let model = HermesRunReviewModel(
            service: HermesRunReviewServiceStub(mode: .pending(events: [event]))
        )
        model.runIDInput = runID.rawValue

        model.startLoading()
        await model.waitForCurrentLoad()

        XCTAssertEqual(
            model.phase,
            .completed(HermesRunReviewSnapshot(status: .completed, events: [event]))
        )
    }

    func testStreamCompletionWithoutTerminalEventHasExplicitCompletedState() async throws {
        let runID = try XCTUnwrap(HermesRunID(rawValue: "opaque-empty-events"))
        let model = HermesRunReviewModel(
            service: HermesRunReviewServiceStub(mode: .finished(events: []))
        )
        model.runIDInput = runID.rawValue

        model.startLoading()
        await model.waitForCurrentLoad()

        XCTAssertEqual(
            model.phase,
            .completed(HermesRunReviewSnapshot(status: .running, events: []))
        )
    }

    func testRetentionDropsOldestEventsAndReportsDiscardCount() async throws {
        let runID = try XCTUnwrap(HermesRunID(rawValue: "opaque-bounded"))
        let events = (1...5).map { value in
            HermesRunEvent.reasoningAvailable(
                HermesEventMetadata(runID: runID, timestamp: "event-\(value)")
            )
        }
        let model = HermesRunReviewModel(
            service: HermesRunReviewServiceStub(mode: .finished(events: events)),
            maximumRetainedEvents: 3
        )
        model.runIDInput = runID.rawValue

        model.startLoading()
        await model.waitForCurrentLoad()

        let expected = HermesRunReviewSnapshot(
            status: .running,
            events: Array(events.suffix(3)),
            discardedEventCount: 2
        )
        XCTAssertEqual(model.phase, HermesRunReviewModel.Phase.completed(expected))
    }

    func testStreamErrorIsSanitizedAndRetainsOnlyVerifiedPartialEvents() async throws {
        let runID = try XCTUnwrap(HermesRunID(rawValue: "must-not-appear-in-error"))
        let event = HermesRunEvent.reasoningAvailable(
            HermesEventMetadata(runID: runID, timestamp: nil)
        )
        let service = HermesRunReviewServiceStub(mode: .streamFailure(
            events: [event],
            message: "provider failed for \(runID.rawValue) token-secret"
        ))
        let model = HermesRunReviewModel(service: service)
        model.runIDInput = runID.rawValue

        model.startLoading()
        await model.waitForCurrentLoad()

        guard case .failed(let message, let partialSnapshot) = model.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertEqual(
            message,
            "Unable to load this Hermes run. No run identifier was included in this error."
        )
        XCTAssertFalse(message.contains(runID.rawValue))
        XCTAssertFalse(message.contains("token-secret"))
        XCTAssertEqual(
            partialSnapshot,
            HermesRunReviewSnapshot(status: .running, events: [event])
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
        await eventually { await service.callCount == 1 }
        await service.setMode(.finished(events: []))
        model.runIDInput = secondRunID.rawValue
        model.startLoading()
        await model.waitForCurrentLoad()

        let expected = HermesRunReviewModel.Phase.completed(
            HermesRunReviewSnapshot(status: .running, events: [])
        )
        XCTAssertEqual(model.phase, expected)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.phase, expected)
    }

    func testRecentRunPickerUsesOpaqueSelectionWithoutDisplayContract() throws {
        let runID = try XCTUnwrap(HermesRunID(rawValue: "opaque-recent"))
        let model = HermesRunReviewModel(
            service: HermesRunReviewServiceStub(mode: .finished(events: [])),
            recentRuns: [runID]
        )

        model.selectRecentRun(runID)

        XCTAssertEqual(model.selectedRecentRun, runID)
        XCTAssertEqual(model.runIDInput, runID.rawValue)
        XCTAssertEqual(model.recentRuns.count, 1)
    }

    private func eventually(
        _ condition: @escaping @MainActor () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<1_000 {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not satisfied", file: file, line: line)
    }
}

private actor HermesRunReviewServiceStub: HermesRunReviewServicing {
    enum Mode: Sendable {
        case finished(events: [HermesRunEvent])
        case pending(events: [HermesRunEvent])
        case streamFailure(events: [HermesRunEvent], message: String)
        case delayed
        case delayedIgnoringCancellation
    }

    private var mode: Mode
    private(set) var callCount = 0
    private let terminationProbe = HermesStreamTerminationProbe()

    var streamTerminationCount: Int {
        get async { await terminationProbe.count }
    }

    init(mode: Mode) {
        self.mode = mode
    }

    func setMode(_ mode: Mode) {
        self.mode = mode
    }

    func currentStreamTerminationCount() async -> Int {
        await terminationProbe.count
    }

    func openReview(for runID: HermesRunID) async throws -> HermesRunReviewSession {
        callCount += 1
        let activeMode = mode
        switch activeMode {
        case .finished(let events):
            return HermesRunReviewSession(status: .running, events: stream(events: events))
        case .pending(let events):
            return HermesRunReviewSession(status: .running, events: pendingStream(events: events))
        case .streamFailure(let events, let message):
            return HermesRunReviewSession(
                status: .running,
                events: stream(events: events, failure: HermesRunReviewTestError.service(message))
            )
        case .delayed:
            try await Task.sleep(for: .seconds(30))
            return HermesRunReviewSession(status: .running, events: stream(events: []))
        case .delayedIgnoringCancellation:
            try? await Task.sleep(for: .milliseconds(100))
            return HermesRunReviewSession(status: .running, events: stream(events: []))
        }
    }

    private func stream(
        events: [HermesRunEvent],
        failure: Error? = nil
    ) -> AsyncThrowingStream<HermesRunEvent, Error> {
        AsyncThrowingStream { continuation in
            events.forEach { continuation.yield($0) }
            if let failure {
                continuation.finish(throwing: failure)
            } else {
                continuation.finish()
            }
        }
    }

    private func pendingStream(
        events: [HermesRunEvent]
    ) -> AsyncThrowingStream<HermesRunEvent, Error> {
        let terminationProbe = terminationProbe
        return AsyncThrowingStream { continuation in
            let task = Task {
                events.forEach { continuation.yield($0) }
                do {
                    try await Task.sleep(for: .seconds(30))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: CancellationError())
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Task { await terminationProbe.markTerminated() }
            }
        }
    }
}

private actor HermesStreamTerminationProbe {
    private(set) var count = 0

    func markTerminated() {
        count += 1
    }
}

private enum HermesRunReviewTestError: Error {
    case service(String)
}

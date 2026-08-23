import Dispatch
import XCTest
@testable import WarRoomAppleInfrastructure

final class NetworkTerminalStateCoordinatorTests: XCTestCase {
    func testCancelBeforeResponseWaitFinishesResponseAndStreamExactlyOnce() async throws {
        let cancellations = LockedCounter()
        let coordinator = try makeCoordinator(cancellations: cancellations)
        let stream = try coordinator.takeStream()

        XCTAssertTrue(coordinator.cancel())
        XCTAssertFalse(coordinator.cancel())
        XCTAssertFalse(coordinator.timeout())
        XCTAssertEqual(cancellations.value, 1)

        await assertResponseFailure(coordinator, equals: .cancelled)
        await assertStreamFailure(stream, equals: .cancelled)
        XCTAssertEqual(
            coordinator.snapshot(),
            NetworkTerminalSnapshot(
                phase: .terminal(.failed(.cancelled)),
                responsePublished: false,
                connectionCancelInvoked: true
            )
        )
    }

    func testConnectionErrorBeforeCancelWinsAndLateEventsAreIgnored() async throws {
        let cancellations = LockedCounter()
        let coordinator = try makeCoordinator(cancellations: cancellations)
        let stream = try coordinator.takeStream()
        let waiter = Task { try await coordinator.awaitResponse() }
        await Task.yield()

        XCTAssertTrue(coordinator.fail(.connection(.connectionReset)))
        XCTAssertFalse(coordinator.cancel())
        XCTAssertEqual(coordinator.publishResponse(204), .ignoredAfterTerminal)
        XCTAssertEqual(coordinator.receive(Data([0x01])), .ignoredAfterTerminal)

        switch await waiter.result {
        case .success:
            XCTFail("Expected a redacted connection error")
        case let .failure(error):
            XCTAssertEqual(error as? NetworkTerminalError, .connection(.connectionReset))
        }
        await assertStreamFailure(stream, equals: .connection(.connectionReset))
        XCTAssertEqual(cancellations.value, 1)
    }

    func testSuccessBeforeTimeoutCompletesStreamAndIgnoresTimeout() async throws {
        let cancellations = LockedCounter()
        let coordinator = try makeCoordinator(cancellations: cancellations)
        let stream = try coordinator.takeStream()
        let waiter = Task { try await coordinator.awaitResponse() }

        XCTAssertEqual(coordinator.publishResponse(200), .accepted)
        XCTAssertEqual(coordinator.receive(Data("ok".utf8)), .accepted)
        XCTAssertTrue(coordinator.finish())
        XCTAssertFalse(coordinator.timeout())
        let response = try await waiter.value
        XCTAssertEqual(response, 200)

        var received: [Data] = []
        for try await element in stream {
            received.append(element)
        }
        XCTAssertEqual(received, [Data("ok".utf8)])
        XCTAssertEqual(cancellations.value, 1)
        XCTAssertEqual(coordinator.snapshot().phase, .terminal(.completed))
    }

    func testTaskCancellationWinsAgainstLateResponse() async throws {
        let cancellations = LockedCounter()
        let coordinator = try makeCoordinator(cancellations: cancellations)
        let waiter = Task { try await coordinator.awaitResponse() }
        await Task.yield()

        waiter.cancel()
        switch await waiter.result {
        case .success:
            XCTFail("Expected cancellation")
        case let .failure(error):
            XCTAssertEqual(error as? NetworkTerminalError, .cancelled)
        }
        XCTAssertEqual(coordinator.publishResponse(200), .ignoredAfterTerminal)
        XCTAssertEqual(cancellations.value, 1)
    }

    func testConcurrentTerminalCallbacksChooseOneWinnerAndResumeOnce() async throws {
        for _ in 0..<200 {
            let cancellations = LockedCounter()
            let coordinator = try makeCoordinator(cancellations: cancellations)
            let stream = try coordinator.takeStream()
            let responseWaiter = Task { try await coordinator.awaitResponse() }
            await Task.yield()

            DispatchQueue.concurrentPerform(iterations: 12) { index in
                switch index % 4 {
                case 0:
                    coordinator.cancel()
                case 1:
                    coordinator.timeout()
                case 2:
                    coordinator.fail(.connection(.networkUnavailable))
                default:
                    coordinator.fail(.protocolFailure(.unexpectedEndOfStream))
                }
            }

            let terminalError: NetworkTerminalError
            switch await responseWaiter.result {
            case .success:
                XCTFail("A terminal race cannot produce a response")
                return
            case let .failure(error):
                guard let typedError = error as? NetworkTerminalError else {
                    XCTFail("Expected a typed redacted error")
                    return
                }
                terminalError = typedError
            }

            await assertStreamFailure(stream, equals: terminalError)
            XCTAssertEqual(
                coordinator.snapshot().phase,
                .terminal(.failed(terminalError))
            )
            XCTAssertEqual(cancellations.value, 1)
        }
    }

    func testFiniteBufferOverflowFailsClosed() async throws {
        let cancellations = LockedCounter()
        let coordinator = try NetworkTerminalStateCoordinator<Int, Data>(
            bufferingLimit: 1,
            cancelConnection: { cancellations.increment() }
        )
        let stream = try coordinator.takeStream()
        XCTAssertEqual(coordinator.publishResponse(200), .accepted)
        XCTAssertEqual(coordinator.receive(Data([0x01])), .accepted)
        XCTAssertEqual(coordinator.receive(Data([0x02])), .rejectedBufferOverflow)
        XCTAssertEqual(cancellations.value, 1)

        var iterator = stream.makeAsyncIterator()
        let firstElement = try await iterator.next()
        XCTAssertEqual(firstElement, Data([0x01]))
        do {
            _ = try await iterator.next()
            XCTFail("Expected buffer overflow")
        } catch {
            XCTAssertEqual(error as? NetworkTerminalError, .streamBufferExceeded(limit: 1))
        }
    }

    func testResponseAndStreamMayEachBeConsumedOnlyOnce() async throws {
        let coordinator = try makeCoordinator(cancellations: LockedCounter())
        _ = try coordinator.takeStream()
        XCTAssertThrowsError(try coordinator.takeStream()) { error in
            XCTAssertEqual(error as? NetworkTerminalError, .streamAlreadyTaken)
        }

        XCTAssertEqual(coordinator.publishResponse(200), .accepted)
        let response = try await coordinator.awaitResponse()
        XCTAssertEqual(response, 200)
        do {
            _ = try await coordinator.awaitResponse()
            XCTFail("Expected a single response consumer")
        } catch {
            XCTAssertEqual(error as? NetworkTerminalError, .responseAlreadyAwaited)
        }
    }

    func testDuplicateResponseDoesNotReplaceFirstResponse() async throws {
        let coordinator = try makeCoordinator(cancellations: LockedCounter())
        XCTAssertEqual(coordinator.publishResponse(200), .accepted)
        XCTAssertEqual(coordinator.publishResponse(500), .ignoredDuplicateResponse)
        let response = try await coordinator.awaitResponse()
        XCTAssertEqual(response, 200)
    }

    func testCompletionWithoutResponseFailsBothConsumers() async throws {
        let cancellations = LockedCounter()
        let coordinator = try makeCoordinator(cancellations: cancellations)
        let stream = try coordinator.takeStream()

        XCTAssertTrue(coordinator.finish())
        await assertResponseFailure(coordinator, equals: .completedWithoutResponse)
        await assertStreamFailure(stream, equals: .completedWithoutResponse)
        XCTAssertEqual(cancellations.value, 1)
    }

    func testRejectsInvalidBufferLimitWithoutCreatingCoordinator() {
        XCTAssertThrowsError(
            try NetworkTerminalStateCoordinator<Int, Data>(
                bufferingLimit: 0,
                cancelConnection: {}
            )
        ) { error in
            XCTAssertEqual(error as? NetworkTerminalError, .invalidBufferLimit)
        }
    }

    func testErrorsNeverEmbedPrivateNetworkDetails() {
        let errors: [NetworkTerminalError] = [
            .invalidBufferLimit,
            .cancelled,
            .timedOut,
            .connection(.tlsHandshake),
            .protocolFailure(.invalidHeader),
            .streamBufferExceeded(limit: 8),
            .completedWithoutResponse,
            .responseAlreadyAwaited,
            .streamAlreadyTaken,
        ]
        for error in errors {
            let description = error.localizedDescription
            XCTAssertFalse(description.contains("https://private.example.test"))
            XCTAssertFalse(description.contains("Authorization"))
            XCTAssertFalse(description.contains("secret"))
        }
    }

    private func makeCoordinator(
        cancellations: LockedCounter
    ) throws -> NetworkTerminalStateCoordinator<Int, Data> {
        try NetworkTerminalStateCoordinator(
            bufferingLimit: 4,
            cancelConnection: { cancellations.increment() }
        )
    }

    private func assertResponseFailure(
        _ coordinator: NetworkTerminalStateCoordinator<Int, Data>,
        equals expected: NetworkTerminalError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await coordinator.awaitResponse()
            XCTFail("Expected response failure", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? NetworkTerminalError, expected, file: file, line: line)
        }
    }

    private func assertStreamFailure(
        _ stream: AsyncThrowingStream<Data, Error>,
        equals expected: NetworkTerminalError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            for try await _ in stream {}
            XCTFail("Expected stream failure", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? NetworkTerminalError, expected, file: file, line: line)
        }
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.withLock { storedValue }
    }

    func increment() {
        lock.withLock { storedValue += 1 }
    }
}

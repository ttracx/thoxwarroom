import Foundation
import WarRoomHermes

struct HermesRunReviewSnapshot: Equatable, Sendable {
    let status: HermesRunStatus
    let events: [HermesRunEvent]
    let discardedEventCount: Int

    init(
        status: HermesRunStatus,
        events: [HermesRunEvent],
        discardedEventCount: Int = 0
    ) {
        self.status = status
        self.events = events
        self.discardedEventCount = discardedEventCount
    }
}

@MainActor
final class HermesRunReviewModel: ObservableObject {
    enum Phase: Equatable {
        case empty
        case loading
        case live(HermesRunReviewSnapshot)
        case completed(HermesRunReviewSnapshot)
        case failed(String, partialSnapshot: HermesRunReviewSnapshot?)
        case cancelled
    }

    @Published var runIDInput = ""
    @Published private(set) var phase: Phase = .empty
    @Published private(set) var selectedRecentRun: HermesRunID?

    let recentRuns: [HermesRunID]
    private let service: any HermesRunReviewServicing
    private let maximumRetainedEvents: Int
    private var loadTask: Task<Void, Never>?
    private var generation = 0

    init(
        service: any HermesRunReviewServicing,
        recentRuns: [HermesRunID] = [],
        maximumRetainedEvents: Int = 200
    ) {
        self.service = service
        self.recentRuns = Array(recentRuns.prefix(20))
        self.maximumRetainedEvents = min(max(maximumRetainedEvents, 1), 1_000)
    }

    deinit {
        loadTask?.cancel()
    }

    func selectRecentRun(_ runID: HermesRunID?) {
        selectedRecentRun = runID
        if let runID {
            runIDInput = runID.rawValue
        }
    }

    func startLoading() {
        loadTask?.cancel()
        generation += 1
        let activeGeneration = generation
        let trimmedInput = runIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let runID = HermesRunID(rawValue: trimmedInput) else {
            phase = .failed("Enter a valid opaque run identifier.", partialSnapshot: nil)
            return
        }

        phase = .loading
        let service = service
        let maximumRetainedEvents = maximumRetainedEvents
        loadTask = Task { [weak self] in
            guard let self else { return }
            var snapshot: HermesRunReviewSnapshot?
            do {
                let session = try await service.openReview(for: runID)
                try Task.checkCancellation()
                guard activeGeneration == generation else { return }

                let initialSnapshot = HermesRunReviewSnapshot(status: session.status, events: [])
                snapshot = initialSnapshot
                phase = .live(initialSnapshot)

                for try await event in session.events {
                    try Task.checkCancellation()
                    guard activeGeneration == generation, let currentSnapshot = snapshot else { return }
                    let updatedSnapshot = Self.appending(
                        event,
                        to: currentSnapshot,
                        maximumRetainedEvents: maximumRetainedEvents
                    )
                    snapshot = updatedSnapshot
                    if Self.isTerminal(event) {
                        phase = .completed(updatedSnapshot)
                        loadTask = nil
                        return
                    }
                    phase = .live(updatedSnapshot)
                }

                try Task.checkCancellation()
                guard activeGeneration == generation, let snapshot else { return }
                phase = .completed(snapshot)
                loadTask = nil
            } catch is CancellationError {
                guard activeGeneration == generation else { return }
                phase = .cancelled
                loadTask = nil
            } catch {
                guard activeGeneration == generation else { return }
                phase = .failed(
                    Self.safeErrorMessage(for: error),
                    partialSnapshot: snapshot
                )
                loadTask = nil
            }
        }
    }

    func cancelLoading() {
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        phase = .cancelled
    }

    func retry() {
        startLoading()
    }

    var canRefresh: Bool {
        guard HermesRunID(rawValue: runIDInput.trimmingCharacters(in: .whitespacesAndNewlines)) != nil else {
            return false
        }
        switch phase {
        case .loading, .live:
            return false
        case .empty, .completed, .failed, .cancelled:
            return true
        }
    }

    func waitForCurrentLoad() async {
        await loadTask?.value
    }

    private static func appending(
        _ event: HermesRunEvent,
        to snapshot: HermesRunReviewSnapshot,
        maximumRetainedEvents: Int
    ) -> HermesRunReviewSnapshot {
        var events = snapshot.events
        var discardedEventCount = snapshot.discardedEventCount
        if events.count == maximumRetainedEvents {
            events.removeFirst()
            discardedEventCount += 1
        }
        events.append(event)
        return HermesRunReviewSnapshot(
            status: terminalStatus(for: event) ?? snapshot.status,
            events: events,
            discardedEventCount: discardedEventCount
        )
    }

    private static func terminalStatus(for event: HermesRunEvent) -> HermesRunStatus? {
        switch event {
        case .runCompleted: .completed
        case .runFailed: .failed
        case .runCancelled: .cancelled
        default: nil
        }
    }

    private static func isTerminal(_ event: HermesRunEvent) -> Bool {
        terminalStatus(for: event) != nil
    }

    private static func safeErrorMessage(for error: Error) -> String {
        if let clientError = error as? HermesClientError {
            switch clientError {
            case .requestTooLarge, .responseTooLarge:
                return "Hermes returned more data than this review surface safely accepts."
            case .invalidResponse:
                return "Hermes returned a response that could not be verified."
            case .invalidRunRoute:
                return "The run identifier cannot be used safely in a request path."
            case .unexpectedStatus, .approvalUnavailable:
                return "Hermes could not load this run. No run identifier was included in this error."
            }
        }
        if error is HermesSSEError {
            return "Hermes event data could not be verified. No unverified event payload was retained."
        }
        return "Unable to load this Hermes run. No run identifier was included in this error."
    }
}

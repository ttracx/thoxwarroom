import Foundation
import WarRoomHermes

struct HermesRunReviewSnapshot: Equatable, Sendable {
    let status: HermesRunStatus
    let events: [HermesRunEvent]
}

@MainActor
final class HermesRunReviewModel: ObservableObject {
    enum Phase: Equatable {
        case empty
        case loading
        case loaded(HermesRunReviewSnapshot)
        case failed(String)
        case cancelled
    }

    @Published var runIDInput = ""
    @Published private(set) var phase: Phase = .empty
    @Published private(set) var selectedRecentRun: HermesRunID?

    let recentRuns: [HermesRunID]
    private let service: any HermesRunReviewServicing
    private var loadTask: Task<Void, Never>?
    private var generation = 0

    init(
        service: any HermesRunReviewServicing,
        recentRuns: [HermesRunID] = []
    ) {
        self.service = service
        self.recentRuns = Array(recentRuns.prefix(20))
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
            phase = .failed("Enter a valid opaque run identifier.")
            return
        }

        phase = .loading
        let service = service
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let status = service.status(for: runID)
                async let events = service.bufferedEvents(for: runID)
                let (statusResponse, bufferedEvents) = try await (status, events)
                let snapshot = HermesRunReviewSnapshot(
                    status: statusResponse.status,
                    events: bufferedEvents
                )
                try Task.checkCancellation()
                guard activeGeneration == generation else { return }
                phase = .loaded(snapshot)
                loadTask = nil
            } catch is CancellationError {
                guard activeGeneration == generation else { return }
                phase = .cancelled
                loadTask = nil
            } catch {
                guard activeGeneration == generation else { return }
                phase = .failed(Self.safeErrorMessage(for: error))
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

    func waitForCurrentLoad() async {
        await loadTask?.value
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
            return "Hermes event data could not be verified. No event payload was retained."
        }
        return "Unable to load this Hermes run. No run identifier was included in this error."
    }
}

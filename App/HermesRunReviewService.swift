import Foundation
import WarRoomHermes

struct HermesRunReviewSession: Sendable {
    let status: HermesRunStatus
    let events: AsyncThrowingStream<HermesRunEvent, Error>
}

/// Read-only Hermes boundary. It intentionally exposes no approval or stop operation.
protocol HermesRunReviewServicing: Sendable {
    func openReview(for runID: HermesRunID) async throws -> HermesRunReviewSession
}

struct HermesAPIReadOnlyReviewService: HermesRunReviewServicing, Sendable {
    private let client: HermesAPIClient
    private let streamingClient: HermesEventStreamingClient

    init(client: HermesAPIClient, streamingClient: HermesEventStreamingClient) {
        self.client = client
        self.streamingClient = streamingClient
    }

    func openReview(for runID: HermesRunID) async throws -> HermesRunReviewSession {
        async let status = client.status(runID: runID)
        async let events = streamingClient.events(runID: runID)
        let values = try await (status, events)
        return HermesRunReviewSession(status: values.0.status, events: values.1)
    }
}

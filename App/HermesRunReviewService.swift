import Foundation
import WarRoomHermes

/// Read-only Hermes boundary. It intentionally exposes no approval or stop operation.
protocol HermesRunReviewServicing: Sendable {
    func status(for runID: HermesRunID) async throws -> HermesRunStatusResponse
    func bufferedEvents(for runID: HermesRunID) async throws -> [HermesRunEvent]
}

struct HermesAPIReadOnlyReviewService: HermesRunReviewServicing, Sendable {
    private let client: HermesAPIClient

    init(client: HermesAPIClient) {
        self.client = client
    }

    func status(for runID: HermesRunID) async throws -> HermesRunStatusResponse {
        try await client.status(runID: runID)
    }

    func bufferedEvents(for runID: HermesRunID) async throws -> [HermesRunEvent] {
        try await client.events(runID: runID)
    }
}

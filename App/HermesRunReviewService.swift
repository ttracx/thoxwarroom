import Foundation
import WarRoomHermes

/// Read-only Hermes boundary. It intentionally exposes no approval or stop operation.
protocol HermesRunReviewServicing: Sendable {
    func loadSnapshot(for runID: HermesRunID) async throws -> HermesRunReviewSnapshot
}

struct HermesAPIReadOnlyReviewService: HermesRunReviewServicing, Sendable {
    private let client: HermesAPIClient

    init(client: HermesAPIClient) {
        self.client = client
    }

    func loadSnapshot(for runID: HermesRunID) async throws -> HermesRunReviewSnapshot {
        async let status = client.status(runID: runID)
        async let events = client.events(runID: runID)
        let values = try await (status, events)
        return HermesRunReviewSnapshot(status: values.0.status, events: values.1)
    }
}

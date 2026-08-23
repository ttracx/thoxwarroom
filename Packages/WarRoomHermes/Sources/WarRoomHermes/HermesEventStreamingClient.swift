import Foundation
import WarRoomCore

/// HTTP status plus an incrementally delivered Hermes response body.
public struct HermesProviderByteStream: Sendable {
    public let statusCode: Int
    public let bytes: AsyncThrowingStream<Data, Error>

    public init(statusCode: Int, bytes: AsyncThrowingStream<Data, Error>) {
        self.statusCode = statusCode
        self.bytes = bytes
    }
}

/// Transport seam for a response body that must not be buffered in memory.
public protocol HermesEventStreamingTransport: Sendable {
    func stream(
        _ request: ProviderRequest,
        to endpoint: ValidatedEndpoint,
        credential: ProviderCredential?
    ) async throws -> HermesProviderByteStream
}

/// Converts a live Hermes SSE byte response into bounded typed run events.
public struct HermesEventStreamingClient: Sendable {
    private let transport: any HermesEventStreamingTransport
    private let endpoint: ValidatedEndpoint
    private let credential: ProviderCredential?
    private let limits: HermesClientLimits

    public init(
        transport: any HermesEventStreamingTransport,
        endpoint: ValidatedEndpoint,
        credential: ProviderCredential? = nil,
        limits: HermesClientLimits = .default
    ) {
        self.transport = transport
        self.endpoint = endpoint
        self.credential = credential
        self.limits = limits
    }

    /// Opens the captured `GET /v1/runs/{opaque-id}/events` SSE route.
    ///
    /// The returned stream owns a child task. Cancelling iteration cancels that
    /// task; concrete transports must also stop their underlying network work
    /// when their byte stream terminates.
    public func events(
        runID: HermesRunID
    ) async throws -> AsyncThrowingStream<HermesRunEvent, Error> {
        try Task.checkCancellation()
        let request = try ProviderRequest(
            method: .get,
            relativePath: try HermesRunRoute.path(runID, suffix: "/events")
        )
        let response = try await transport.stream(
            request,
            to: endpoint,
            credential: credential
        )
        try Task.checkCancellation()
        guard response.statusCode == 200 else {
            throw HermesClientError.unexpectedStatus(response.statusCode)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var parser = try HermesSSEParser(
                        maximumBufferedBytes: limits.maximumResponseBodyBytes,
                        maximumEventBytes: limits.maximumSSEEventBytes
                    )
                    for try await chunk in response.bytes {
                        try Task.checkCancellation()
                        for event in try parser.append(chunk) {
                            try validate(event, expectedRunID: runID)
                            continuation.yield(event)
                        }
                    }
                    for event in try parser.finish() {
                        try validate(event, expectedRunID: runID)
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func validate(_ event: HermesRunEvent, expectedRunID: HermesRunID) throws {
        guard event.runID == nil || event.runID == expectedRunID else {
            throw HermesClientError.invalidResponse
        }
    }
}

enum HermesRunRoute {
    static func path(_ runID: HermesRunID, suffix: String = "") throws -> String {
        guard let segment = percentEncodedPathSegment(runID.rawValue) else {
            throw HermesClientError.invalidRunRoute
        }
        return "/v1/runs/\(segment)\(suffix)"
    }

    private static func percentEncodedPathSegment(_ value: String) -> String? {
        guard !value.contains("/"), !value.contains("\\"), !value.contains("%"),
              !value.contains("?"), !value.contains("#"), value != ".", value != ".." else {
            return nil
        }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~".utf8)
        var result = ""
        for byte in value.utf8 {
            if allowed.contains(byte) {
                result.append(Character(UnicodeScalar(byte)))
            } else {
                result += String(format: "%%%02X", byte)
            }
        }
        guard !result.isEmpty, !result.localizedCaseInsensitiveContains("%2F") else { return nil }
        return result
    }
}

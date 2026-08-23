import Foundation
import WarRoomCore

public struct HermesClientLimits: Equatable, Sendable {
    private static let hardMaximumBytes = 64 * 1_024 * 1_024

    public let maximumRequestBodyBytes: Int
    public let maximumResponseBodyBytes: Int
    public let maximumSSEEventBytes: Int

    public init() {
        self.maximumRequestBodyBytes = 10 * 1_024 * 1_024
        self.maximumResponseBodyBytes = 10 * 1_024 * 1_024
        self.maximumSSEEventBytes = 256 * 1_024
    }

    public init(
        maximumRequestBodyBytes: Int,
        maximumResponseBodyBytes: Int,
        maximumSSEEventBytes: Int
    ) throws {
        guard (1...Self.hardMaximumBytes).contains(maximumRequestBodyBytes),
              (1...Self.hardMaximumBytes).contains(maximumResponseBodyBytes),
              (1...maximumResponseBodyBytes).contains(maximumSSEEventBytes) else {
            throw HermesLimitError.invalidClientLimits
        }
        self.maximumRequestBodyBytes = maximumRequestBodyBytes
        self.maximumResponseBodyBytes = maximumResponseBodyBytes
        self.maximumSSEEventBytes = maximumSSEEventBytes
    }

    public static let `default` = HermesClientLimits()
}

public enum HermesLimitError: Error, Equatable, Sendable {
    case invalidClientLimits
    case invalidSSELimits
}

public enum HermesClientError: Error, Equatable, Sendable {
    case requestTooLarge
    case responseTooLarge
    case unexpectedStatus(Int)
    case invalidResponse
    case invalidRunRoute
    case approvalUnavailable
}

public struct HermesAPIClient: Sendable {
    private let transport: any ProviderTransport
    private let endpoint: ValidatedEndpoint
    private let credential: ProviderCredential?
    private let limits: HermesClientLimits

    public init(
        transport: any ProviderTransport,
        endpoint: ValidatedEndpoint,
        credential: ProviderCredential? = nil,
        limits: HermesClientLimits = .default
    ) {
        self.transport = transport
        self.endpoint = endpoint
        self.credential = credential
        self.limits = limits
    }

    public func capabilities() async throws -> HermesCapabilitiesResponse {
        try await sendDecodable(method: .get, path: "/v1/capabilities", expectedStatus: 200)
    }

    public func submit(_ request: HermesRunSubmitRequest) async throws -> HermesRunSubmitResponse {
        let body = try encodeBounded(request)
        let response: HermesRunSubmitResponse = try await sendDecodable(
            method: .post,
            path: "/v1/runs",
            body: body,
            expectedStatus: 202
        )
        guard response.status == .started else { throw HermesClientError.invalidResponse }
        return response
    }

    public func status(runID: HermesRunID) async throws -> HermesRunStatusResponse {
        let response: HermesRunStatusResponse = try await sendDecodable(
            method: .get,
            path: try runPath(runID),
            expectedStatus: 200
        )
        guard response.runID == runID else { throw HermesClientError.invalidResponse }
        return response
    }

    public func events(runID: HermesRunID) async throws -> [HermesRunEvent] {
        try Task.checkCancellation()
        let request = try ProviderRequest(
            method: .get,
            relativePath: try HermesRunRoute.path(runID, suffix: "/events")
        )
        let response = try await transport.send(request, to: endpoint, credential: credential)
        try Task.checkCancellation()
        guard response.statusCode == 200 else { throw HermesClientError.unexpectedStatus(response.statusCode) }
        try validateResponseSize(response.body)
        var parser = try HermesSSEParser(
            maximumBufferedBytes: limits.maximumResponseBodyBytes,
            maximumEventBytes: limits.maximumSSEEventBytes
        )
        var events = try parser.append(response.body)
        events.append(contentsOf: try parser.finish())
        guard events.allSatisfy({ $0.runID == nil || $0.runID == runID }) else {
            throw HermesClientError.invalidResponse
        }
        try Task.checkCancellation()
        return events
    }

    /// Raw mutation primitive available only to the audited coordinator in this module.
    func approve(
        runID: HermesRunID,
        request: HermesApprovalRequest
    ) async throws -> HermesApprovalResponse {
        try Task.checkCancellation()
        let providerRequest = try ProviderRequest(
            method: .post,
            relativePath: try HermesRunRoute.path(runID, suffix: "/approval"),
            body: try encodeBounded(request)
        )
        let response = try await transport.send(providerRequest, to: endpoint, credential: credential)
        try Task.checkCancellation()
        if response.statusCode == 409 { throw HermesClientError.approvalUnavailable }
        guard response.statusCode == 200 else { throw HermesClientError.unexpectedStatus(response.statusCode) }
        let decoded = try decodeBounded(HermesApprovalResponse.self, from: response.body)
        guard decoded.runID == runID, decoded.choice == request.choice else {
            throw HermesClientError.invalidResponse
        }
        return decoded
    }

    /// Raw mutation primitive available only to the audited coordinator in this module.
    func stop(
        runID: HermesRunID,
        request: HermesStopRequest = HermesStopRequest()
    ) async throws -> HermesStopResponse {
        _ = request // Marker for forward-compatible request fields; current wire body is empty.
        try Task.checkCancellation()
        let providerRequest = try ProviderRequest(
            method: .post,
            relativePath: try HermesRunRoute.path(runID, suffix: "/stop")
        )
        let response = try await transport.send(providerRequest, to: endpoint, credential: credential)
        try Task.checkCancellation()
        guard response.statusCode == 200 || response.statusCode == 202 else {
            throw HermesClientError.unexpectedStatus(response.statusCode)
        }
        try validateResponseSize(response.body)
        guard !response.body.isEmpty else { return HermesStopResponse(runID: runID, status: nil) }
        let decoded = try decode(HermesStopResponse.self, from: response.body)
        guard decoded.runID == nil || decoded.runID == runID else {
            throw HermesClientError.invalidResponse
        }
        return decoded
    }

    private func sendDecodable<Response: Decodable>(
        method: ProviderRequest.Method,
        path: String,
        body: Data? = nil,
        expectedStatus: Int
    ) async throws -> Response {
        try Task.checkCancellation()
        let request = try ProviderRequest(method: method, relativePath: path, body: body)
        let response = try await transport.send(request, to: endpoint, credential: credential)
        try Task.checkCancellation()
        guard response.statusCode == expectedStatus else {
            throw HermesClientError.unexpectedStatus(response.statusCode)
        }
        return try decodeBounded(Response.self, from: response.body)
    }

    private func encodeBounded<Value: Encodable>(_ value: Value) throws -> Data {
        try Task.checkCancellation()
        let body = try JSONEncoder().encode(value)
        guard body.count <= limits.maximumRequestBodyBytes else { throw HermesClientError.requestTooLarge }
        return body
    }

    private func decodeBounded<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        try validateResponseSize(data)
        return try decode(type, from: data)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw HermesClientError.invalidResponse }
    }

    private func validateResponseSize(_ data: Data) throws {
        guard data.count <= limits.maximumResponseBodyBytes else {
            throw HermesClientError.responseTooLarge
        }
    }

    private func runPath(_ runID: HermesRunID, suffix: String = "") throws -> String {
        try HermesRunRoute.path(runID, suffix: suffix)
    }
}

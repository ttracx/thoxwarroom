import Foundation
import WarRoomCore

/// Clean-room client for the currently captured Open WebUI discovery surface.
public struct OpenWebUIClient: Sendable {
    private let endpoint: ValidatedEndpoint
    private let transport: any ProviderTransport
    private let credential: ProviderCredential?
    private let descriptor: ProviderDescriptor
    private let limits: OpenWebUIResponseLimits

    /// Creates a client without performing network access.
    ///
    /// - Parameters:
    ///   - endpoint: A workspace endpoint already validated by `WarRoomCore`.
    ///   - transport: The caller-owned network execution boundary.
    ///   - credential: An optional opaque credential forwarded only to the transport.
    ///   - descriptor: Capability declaration used to gate product operations.
    ///   - limits: Maximum accepted response size.
    public init(
        endpoint: ValidatedEndpoint,
        transport: any ProviderTransport,
        credential: ProviderCredential? = nil,
        descriptor: ProviderDescriptor = OpenWebUIProvider.descriptor,
        limits: OpenWebUIResponseLimits = .standard
    ) {
        self.endpoint = endpoint
        self.transport = transport
        self.credential = credential
        self.descriptor = descriptor
        self.limits = limits
    }

    /// Fetches and validates the public plain-text health response.
    public func health() async throws -> OpenWebUIHealth {
        let data = try await responseBody(for: .health)
        guard let value = String(data: data, encoding: .utf8) else {
            throw OpenWebUIProviderError.invalidText(endpoint: .health)
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let status = OpenWebUIHealth.Status(rawValue: normalized) else {
            throw OpenWebUIProviderError.invalidHealthResponse
        }
        return OpenWebUIHealth(status: status)
    }

    /// Fetches the public deployment version.
    public func version() async throws -> OpenWebUIVersion {
        let value: OpenWebUIVersion = try await decodedResponse(for: .version)
        guard !value.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenWebUIProviderError.invalidPayload(endpoint: .version)
        }
        return value
    }

    /// Fetches public, non-secret configuration and feature switches.
    public func configuration() async throws -> OpenWebUIConfiguration {
        let value: OpenWebUIConfiguration = try await decodedResponse(for: .configuration)
        guard !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenWebUIProviderError.invalidPayload(endpoint: .configuration)
        }
        return value
    }

    /// Fetches the protected model catalog when the workspace advertises support.
    ///
    /// The authenticated response shape remains provisional until a dedicated
    /// non-production capture is completed.
    public func models() async throws -> OpenWebUIModelCatalog {
        guard descriptor.supports(.modelCatalog) else {
            throw OpenWebUIProviderError.unsupportedCapability(.modelCatalog)
        }
        let value: OpenWebUIModelCatalog = try await decodedResponse(for: .models)
        guard value.data.allSatisfy({ !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw OpenWebUIProviderError.invalidPayload(endpoint: .models)
        }
        return value
    }

    private func decodedResponse<Value: Decodable>(
        for providerEndpoint: OpenWebUIEndpoint
    ) async throws -> Value {
        let data = try await responseBody(for: providerEndpoint)
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw OpenWebUIProviderError.decodingFailed(endpoint: providerEndpoint)
        }
    }

    private func responseBody(for providerEndpoint: OpenWebUIEndpoint) async throws -> Data {
        let request: ProviderRequest
        do {
            request = try ProviderRequest(
                method: .get,
                relativePath: providerEndpoint.rawValue
            )
        } catch {
            // Every path is a package constant. Preserve a typed error if that
            // invariant changes rather than exposing the construction failure.
            throw OpenWebUIProviderError.requestConstructionFailed(endpoint: providerEndpoint)
        }

        let response: ProviderResponse
        do {
            try Task.checkCancellation()
            response = try await transport.send(
                request,
                to: endpoint,
                credential: providerEndpoint == .models ? credential : nil
            )
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw OpenWebUIProviderError.transportFailure(endpoint: providerEndpoint)
        }

        switch response.statusCode {
        case 200:
            break
        case 401:
            throw OpenWebUIProviderError.authenticationRequired(endpoint: providerEndpoint)
        case 403:
            throw OpenWebUIProviderError.accessDenied(endpoint: providerEndpoint)
        default:
            throw OpenWebUIProviderError.unexpectedStatus(
                endpoint: providerEndpoint,
                statusCode: response.statusCode
            )
        }

        guard response.body.count <= limits.maximumResponseBytes else {
            throw OpenWebUIProviderError.responseTooLarge(
                endpoint: providerEndpoint,
                limit: limits.maximumResponseBytes,
                actual: response.body.count
            )
        }
        return response.body
    }
}

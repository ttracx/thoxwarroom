import Foundation
import WarRoomCore

/// Endpoint identities used in typed provider results and errors.
public enum OpenWebUIEndpoint: String, Codable, Equatable, Sendable {
    /// Plain-text liveness endpoint.
    case health = "/health"
    /// Public deployment version endpoint.
    case version = "/api/version"
    /// Public deployment configuration endpoint.
    case configuration = "/api/config"
    /// Protected model-catalog endpoint.
    case models = "/api/models"
}

/// Static metadata for the clean-room Open WebUI provider slice.
public enum OpenWebUIProvider {
    /// The only product capability implemented by WR-004 is model discovery.
    /// Chat, streaming, history, and citations remain intentionally absent.
    public static let descriptor = ProviderDescriptor(
        id: ProviderID(rawValue: "open-webui"),
        displayName: "Open WebUI",
        capabilities: [.modelCatalog]
    )
}

/// Validated response-size policy for Open WebUI provider calls.
public struct OpenWebUIResponseLimits: Equatable, Sendable {
    /// Maximum bytes accepted before text or JSON decoding.
    public let maximumResponseBytes: Int

    /// Creates a response-size policy with a positive byte limit.
    public init(maximumResponseBytes: Int) throws {
        guard maximumResponseBytes > 0 else {
            throw OpenWebUIClientConfigurationError.invalidMaximumResponseBytes
        }
        self.maximumResponseBytes = maximumResponseBytes
    }

    /// One MiB is ample for discovery responses while bounding decoder work.
    public static let standard = OpenWebUIResponseLimits(validatedMaximumResponseBytes: 1_048_576)

    private init(validatedMaximumResponseBytes: Int) {
        maximumResponseBytes = validatedMaximumResponseBytes
    }
}

/// Invalid local client configuration detected before any provider call.
public enum OpenWebUIClientConfigurationError: Error, Equatable, Sendable {
    /// The response byte limit was zero or negative.
    case invalidMaximumResponseBytes
}

/// Stable, non-sensitive failure categories returned by the provider client.
public enum OpenWebUIProviderError: Error, Equatable, Sendable {
    /// The workspace did not advertise a capability required by the operation.
    case unsupportedCapability(ProviderCapability)
    /// The provider request could not be constructed from a package-owned path.
    case requestConstructionFailed(endpoint: OpenWebUIEndpoint)
    /// The transport failed without exposing its potentially sensitive message.
    case transportFailure(endpoint: OpenWebUIEndpoint)
    /// The provider requires a credential.
    case authenticationRequired(endpoint: OpenWebUIEndpoint)
    /// The supplied identity is not authorized for the endpoint.
    case accessDenied(endpoint: OpenWebUIEndpoint)
    /// The provider returned a status outside the captured contract.
    case unexpectedStatus(endpoint: OpenWebUIEndpoint, statusCode: Int)
    /// The body exceeded the local decode limit.
    case responseTooLarge(endpoint: OpenWebUIEndpoint, limit: Int, actual: Int)
    /// A plain-text body was not valid UTF-8.
    case invalidText(endpoint: OpenWebUIEndpoint)
    /// The health body did not contain the captured `OK` state.
    case invalidHealthResponse
    /// A JSON body did not match the endpoint DTO.
    case decodingFailed(endpoint: OpenWebUIEndpoint)
    /// A decoded DTO violated a required semantic invariant.
    case invalidPayload(endpoint: OpenWebUIEndpoint)
}

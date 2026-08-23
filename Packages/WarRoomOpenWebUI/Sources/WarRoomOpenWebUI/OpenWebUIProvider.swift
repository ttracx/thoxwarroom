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
    /// Evidence gate for native chat against the currently captured deployment.
    ///
    /// Route existence and an authentication challenge do not establish a safe
    /// request or response contract. Callers can use this value to explain why
    /// native chat is unavailable without inventing a provider-specific shape.
    public static let nativeChatContract = OpenWebUINativeChatContract.current

    /// The only product capability implemented by WR-004 is model discovery.
    /// Chat capabilities are derived from the evidence gate and therefore stay
    /// absent until every required authenticated contract element is captured.
    public static let descriptor = ProviderDescriptor(
        id: ProviderID(rawValue: "open-webui"),
        displayName: "Open WebUI",
        capabilities: Set([ProviderCapability.modelCatalog])
            .union(nativeChatContract.advertisedCapabilities)
    )
}

/// An authenticated contract element required before native Open WebUI chat
/// can safely be advertised or invoked.
public enum OpenWebUINativeChatEvidenceRequirement: String, Codable, CaseIterable, Hashable, Sendable {
    /// How an externally provisioned bearer credential is issued, refreshed,
    /// revoked, and logged out without collecting a password in the app.
    case credentialLifecycle = "credential_lifecycle"
    /// Authenticated non-streaming request field names, types, and bounds.
    case nonStreamingRequest = "non_streaming_request"
    /// Authenticated non-streaming success response envelope.
    case nonStreamingResponse = "non_streaming_response"
    /// Streaming transport, content type, and connection headers.
    case streamingTransport = "streaming_transport"
    /// Streaming frame schema, ordering rules, and normal termination marker.
    case streamingFrames = "streaming_frames"
    /// Server behavior and client semantics for cancellation.
    case cancellation = "cancellation"
    /// Sanitized authentication, validation, and server error envelopes.
    case errorResponses = "error_responses"
    /// Minimum create, update, list, and get sequence for durable conversation history.
    case durableHistory = "durable_history"
    /// Citation and source field shapes, including their absence semantics.
    case sourceCitations = "source_citations"
}

/// Current readiness of the native Open WebUI chat contract.
public struct OpenWebUINativeChatContract: Equatable, Sendable {
    /// Stable non-sensitive reason suitable for product routing and diagnostics.
    public enum Blocker: String, Codable, Equatable, Sendable {
        case authenticatedCaptureRequired = "authenticated_capture_required"
    }

    /// Why native chat cannot currently be enabled.
    public let blocker: Blocker
    /// Exact evidence still required to define bounded request/response DTOs.
    public let missingEvidence: Set<OpenWebUINativeChatEvidenceRequirement>

    /// `false` until a later, reviewed contract capture replaces this gate.
    public var isAvailable: Bool { false }

    /// Capabilities that can truthfully be advertised from this evidence.
    public var advertisedCapabilities: Set<ProviderCapability> { [] }

    fileprivate static let current = OpenWebUINativeChatContract(
        blocker: .authenticatedCaptureRequired,
        missingEvidence: Set(OpenWebUINativeChatEvidenceRequirement.allCases)
    )

    private init(
        blocker: Blocker,
        missingEvidence: Set<OpenWebUINativeChatEvidenceRequirement>
    ) {
        self.blocker = blocker
        self.missingEvidence = missingEvidence
    }
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

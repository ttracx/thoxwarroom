import Foundation

/// A successful response from the Open WebUI plain-text health endpoint.
public struct OpenWebUIHealth: Equatable, Sendable {
    /// Health states established by the captured public contract.
    public enum Status: String, Sendable {
        case ok = "OK"
    }

    /// The service health state.
    public let status: Status

    public init(status: Status) {
        self.status = status
    }
}

/// Public deployment version metadata.
public struct OpenWebUIVersion: Codable, Equatable, Sendable {
    /// The Open WebUI semantic version reported by the service.
    public let version: String

    public init(version: String) {
        self.version = version
    }
}

/// Public feature switches returned by Open WebUI configuration discovery.
public struct OpenWebUIFeatures: Codable, Equatable, Sendable {
    /// Whether the deployment requires authentication.
    public let auth: Bool
    /// Whether a trusted reverse-proxy header can authenticate users.
    public let authTrustedHeader: Bool
    /// Whether signup requires password confirmation.
    public let enableSignupPasswordConfirmation: Bool
    /// Whether LDAP authentication is enabled.
    public let enableLDAP: Bool
    /// Whether self-service signup is enabled.
    public let enableSignup: Bool
    /// Whether the built-in login form is enabled.
    public let enableLoginForm: Bool
    /// Whether the deployment advertises WebSocket support.
    public let enableWebSocket: Bool

    /// Creates a typed public feature set.
    public init(
        auth: Bool,
        authTrustedHeader: Bool,
        enableSignupPasswordConfirmation: Bool,
        enableLDAP: Bool,
        enableSignup: Bool,
        enableLoginForm: Bool,
        enableWebSocket: Bool
    ) {
        self.auth = auth
        self.authTrustedHeader = authTrustedHeader
        self.enableSignupPasswordConfirmation = enableSignupPasswordConfirmation
        self.enableLDAP = enableLDAP
        self.enableSignup = enableSignup
        self.enableLoginForm = enableLoginForm
        self.enableWebSocket = enableWebSocket
    }

    private enum CodingKeys: String, CodingKey {
        case auth
        case authTrustedHeader = "auth_trusted_header"
        case enableSignupPasswordConfirmation = "enable_signup_password_confirmation"
        case enableLDAP = "enable_ldap"
        case enableSignup = "enable_signup"
        case enableLoginForm = "enable_login_form"
        case enableWebSocket = "enable_websocket"
    }
}

/// Public, non-secret Open WebUI deployment configuration.
public struct OpenWebUIConfiguration: Codable, Equatable, Sendable {
    /// Whether the deployment reports itself operational.
    public let status: Bool
    /// User-visible deployment name.
    public let name: String
    /// Open WebUI version reported by configuration discovery.
    public let version: String
    /// Default locale identifier, or an empty string when none is configured.
    public let defaultLocale: String
    /// Public feature switches.
    public let features: OpenWebUIFeatures

    /// Creates typed public deployment configuration.
    public init(
        status: Bool,
        name: String,
        version: String,
        defaultLocale: String,
        features: OpenWebUIFeatures
    ) {
        self.status = status
        self.name = name
        self.version = version
        self.defaultLocale = defaultLocale
        self.features = features
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case name
        case version
        case defaultLocale = "default_locale"
        case features
    }
}

/// Minimal model metadata accepted by the provisional model-catalog decoder.
///
/// The authenticated live shape has not yet been captured. Only a stable model
/// identifier is required; a display name is retained when present.
public struct OpenWebUIModel: Codable, Equatable, Sendable {
    /// Opaque provider model identifier.
    public let id: String
    /// Optional user-visible model name.
    public let name: String?

    /// Creates minimal model metadata.
    public init(id: String, name: String? = nil) {
        self.id = id
        self.name = name
    }
}

/// Provisional `/api/models` response envelope.
///
/// This DTO deliberately supports only the conservative `{ "data": [...] }`
/// shape. A contract mismatch is surfaced as a typed decoding error instead of
/// silently guessing at another server representation.
public struct OpenWebUIModelCatalog: Codable, Equatable, Sendable {
    /// Models returned by the provider.
    public let data: [OpenWebUIModel]

    /// Creates a model catalog.
    public init(data: [OpenWebUIModel]) {
        self.data = data
    }
}

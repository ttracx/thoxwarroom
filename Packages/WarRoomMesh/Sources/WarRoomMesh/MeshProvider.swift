import Foundation
import WarRoomCore

/// Read-only MeshStack route identity used in non-sensitive errors.
public enum MeshEndpoint: String, Codable, Equatable, Sendable {
    /// User-visible devices in one mesh.
    case devices = "/api/admin/console/devices"
    /// Computed topology for one mesh.
    case topology = "/api/admin/console/topology"
    /// Bounded event history for one mesh.
    case events = "/api/admin/console/events"
}

/// Static provider metadata for the read-only MeshStack slice.
public enum MeshProvider {
    /// The package implements War Room status reads only.
    public static let descriptor = ProviderDescriptor(
        id: ProviderID(rawValue: "meshstack-read-only"),
        displayName: "MeshStack Read-Only",
        capabilities: [.warRoomStatus]
    )
}

/// Validated byte bound applied before JSON decoding.
public struct MeshResponseLimits: Equatable, Sendable {
    /// Absolute ceiling that local configuration cannot exceed.
    public static let hardMaximumResponseBytes = 67_108_864

    /// Maximum response bytes accepted by this client instance.
    public let maximumResponseBytes: Int

    /// Creates a decode bound in the closed range `1...64 MiB`.
    public init(maximumResponseBytes: Int) throws {
        guard (1...Self.hardMaximumResponseBytes).contains(maximumResponseBytes) else {
            throw MeshClientConfigurationError.invalidMaximumResponseBytes
        }
        self.maximumResponseBytes = maximumResponseBytes
    }

    /// Two MiB supports a 500-event page while bounding decoder work.
    public static let standard = MeshResponseLimits(validatedMaximumResponseBytes: 2_097_152)

    private init(validatedMaximumResponseBytes: Int) {
        maximumResponseBytes = validatedMaximumResponseBytes
    }
}

/// Invalid package-local client configuration.
public enum MeshClientConfigurationError: Error, Equatable, Sendable {
    /// The decode bound fell outside `1...64 MiB`.
    case invalidMaximumResponseBytes
}

/// Contract invariant that a decoded response failed to satisfy.
public enum MeshContractViolation: Equatable, Sendable {
    /// The server returned data for a mesh other than the request scope.
    case meshIdentifierMismatch
    /// An envelope count did not equal its returned array size.
    case countMismatch
    /// A required display, type, platform, role, or severity field was blank.
    case blankRequiredField
    /// A response repeated an identity where uniqueness is required.
    case duplicateIdentifier
    /// A topology edge referenced a node absent from the response.
    case edgeReferencesUnknownNode
    /// A topology latency was negative or non-finite.
    case negativeRoundTripTime
}

/// Stable errors that never retain response bodies, credentials, or identifiers.
public enum MeshProviderError: Error, Equatable, Sendable {
    /// Workspace capability declaration does not permit War Room status reads.
    case unsupportedCapability(ProviderCapability)
    /// A package-owned request path or query item violated the core seam.
    case requestConstructionFailed(endpoint: MeshEndpoint)
    /// Transport failed without retaining its potentially sensitive message.
    case transportFailure(endpoint: MeshEndpoint)
    /// Provider requires an authentication credential.
    case authenticationRequired(endpoint: MeshEndpoint)
    /// Authenticated identity lacks access to the requested mesh.
    case accessDenied(endpoint: MeshEndpoint)
    /// Requested read-only resource was not found.
    case notFound(endpoint: MeshEndpoint)
    /// Provider returned a status outside the captured contract.
    case unexpectedStatus(endpoint: MeshEndpoint, statusCode: Int)
    /// Provider body exceeded the configured decode bound.
    case responseTooLarge(endpoint: MeshEndpoint, limit: Int, actual: Int)
    /// Provider JSON did not match the captured DTO.
    case decodingFailed(endpoint: MeshEndpoint)
    /// Decoded data violated an invariant required for safe presentation.
    case contractViolation(endpoint: MeshEndpoint, violation: MeshContractViolation)
}

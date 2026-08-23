import Foundation
import WarRoomCore
import WarRoomHermes

/// Explicit transport policy derived only from the already-validated workspace
/// endpoint. HTTPS is DNS-bound; only loopback HTTP retains URLSession
/// compatibility. A decoded legacy private/hosted HTTP profile remains visible
/// as unsupported and receives DNS-bound transports that reject the scheme.
public enum WorkspaceNetworkTransportMode: Equatable, Sendable {
    case dnsBoundTLS
    case loopbackHTTPCompatibility
    case unsupportedInsecureTransport
}

public struct WorkspaceNetworkTransports: Sendable {
    public let mode: WorkspaceNetworkTransportMode
    public let provider: any ProviderTransport
    public let hermesEvents: any HermesEventStreamingTransport

    public init(
        mode: WorkspaceNetworkTransportMode,
        provider: any ProviderTransport,
        hermesEvents: any HermesEventStreamingTransport
    ) {
        self.mode = mode
        self.provider = provider
        self.hermesEvents = hermesEvents
    }
}

public enum WorkspaceNetworkTransportComposition {
    public static func mode(for endpoint: ValidatedEndpoint) -> WorkspaceNetworkTransportMode {
        if endpoint.url.scheme?.lowercased() == "https" {
            return .dnsBoundTLS
        }
        if endpoint.boundary == .localMachine,
           endpoint.url.scheme?.lowercased() == "http" {
            return .loopbackHTTPCompatibility
        }
        return .unsupportedInsecureTransport
    }

    public static func make(for endpoint: ValidatedEndpoint) -> WorkspaceNetworkTransports {
        switch mode(for: endpoint) {
        case .dnsBoundTLS:
            return WorkspaceNetworkTransports(
                mode: .dnsBoundTLS,
                provider: DNSBoundProviderTransport(),
                hermesEvents: DNSBoundHermesEventStreamingTransport.secureDefault
            )
        case .loopbackHTTPCompatibility:
            return WorkspaceNetworkTransports(
                mode: .loopbackHTTPCompatibility,
                provider: URLSessionProviderTransport(),
                hermesEvents: URLSessionHermesEventStreamingTransport()
            )
        case .unsupportedInsecureTransport:
            // DNS-bound transports are HTTPS-only and therefore fail closed if
            // a legacy private/hosted HTTP profile reaches a feature host.
            return WorkspaceNetworkTransports(
                mode: .unsupportedInsecureTransport,
                provider: DNSBoundProviderTransport(),
                hermesEvents: DNSBoundHermesEventStreamingTransport.secureDefault
            )
        }
    }
}

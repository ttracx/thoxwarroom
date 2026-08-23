import Foundation
import XCTest
@testable import WarRoomAppleInfrastructure
import WarRoomCore

final class WorkspaceNetworkTransportCompositionTests: XCTestCase {
    func testHTTPSUsesDNSBoundTransports() throws {
        let endpoint = try EndpointValidator.validate(
            "https://provider.internal",
            declaredBoundary: .privateNetwork
        )

        let transports = WorkspaceNetworkTransportComposition.make(for: endpoint)

        XCTAssertEqual(transports.mode, .dnsBoundTLS)
        XCTAssertTrue(transports.provider is DNSBoundProviderTransport)
        XCTAssertTrue(transports.hermesEvents is DNSBoundHermesEventStreamingTransport)
    }

    func testLoopbackHTTPRetainsExplicitCompatibilityTransport() throws {
        let endpoint = try EndpointValidator.validate(
            "http://localhost",
            declaredBoundary: .localMachine
        )

        let transports = WorkspaceNetworkTransportComposition.make(for: endpoint)

        XCTAssertEqual(transports.mode, .loopbackHTTPCompatibility)
        XCTAssertTrue(transports.provider is URLSessionProviderTransport)
        XCTAssertTrue(transports.hermesEvents is URLSessionHermesEventStreamingTransport)
    }

    func testDecodedLegacyPrivateHTTPFailsClosed() throws {
        let endpoint = try JSONDecoder().decode(
            ValidatedEndpoint.self,
            from: Data(#"{"url":"http://provider.internal","boundary":"privateNetwork"}"#.utf8)
        )

        let transports = WorkspaceNetworkTransportComposition.make(for: endpoint)

        XCTAssertEqual(transports.mode, .unsupportedInsecureTransport)
        XCTAssertTrue(transports.provider is DNSBoundProviderTransport)
        XCTAssertTrue(transports.hermesEvents is DNSBoundHermesEventStreamingTransport)
    }
}

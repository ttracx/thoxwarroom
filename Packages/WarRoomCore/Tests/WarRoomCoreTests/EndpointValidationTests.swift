import XCTest
@testable import WarRoomCore

final class EndpointValidationTests: XCTestCase {
    func testAcceptsLoopbackHTTPAndNormalizesHostAndTrailingSlash() throws {
        let endpoint = try EndpointValidator.validate(
            "http://LOCALHOST/",
            declaredBoundary: .localMachine
        )

        XCTAssertEqual(endpoint.url.absoluteString, "http://localhost")
        XCTAssertEqual(endpoint.boundary, .localMachine)
    }

    func testAcceptsIPv4AndIPv6Loopback() throws {
        XCTAssertNoThrow(try EndpointValidator.validate(
            "http://127.0.0.1",
            declaredBoundary: .localMachine
        ))
        XCTAssertNoThrow(try EndpointValidator.validate(
            "https://[::1]",
            declaredBoundary: .localMachine
        ))
    }

    func testPrivateAddressRequiresMatchingBoundary() throws {
        XCTAssertThrowsError(try EndpointValidator.validate(
            "https://192.168.1.8",
            declaredBoundary: .hosted,
            hostedAccess: .granted
        )) { error in
            XCTAssertEqual(
                error as? EndpointValidationError,
                .boundaryMismatch(declared: .hosted, detected: .privateNetwork)
            )
        }
    }

    func testPrivateHTTPRequiresExplicitPolicy() throws {
        XCTAssertThrowsError(try EndpointValidator.validate(
            "http://warroom.internal",
            declaredBoundary: .privateNetwork
        )) { error in
            XCTAssertEqual(error as? EndpointValidationError, .insecurePrivateNetworkTransport)
        }

        let policy = EndpointValidationPolicy(allowsPrivateNetworkHTTP: true)
        XCTAssertNoThrow(try EndpointValidator.validate(
            "http://warroom.internal",
            declaredBoundary: .privateNetwork,
            policy: policy
        ))
    }

    func testHostedEndpointRequiresHTTPSAndExplicitAuthorization() throws {
        XCTAssertThrowsError(try EndpointValidator.validate(
            "https://example.com",
            declaredBoundary: .hosted
        )) { error in
            XCTAssertEqual(error as? EndpointValidationError, .hostedAccessNotAuthorized)
        }

        XCTAssertNoThrow(try EndpointValidator.validate(
            "https://example.com",
            declaredBoundary: .hosted,
            hostedAccess: .granted
        ))
        XCTAssertThrowsError(try EndpointValidator.validate(
            "http://example.com",
            declaredBoundary: .hosted,
            hostedAccess: .granted
        ))
    }

    func testRejectsCredentialsQueryFragmentAndTraversal() {
        let cases: [(String, EndpointValidationError)] = [
            ("https://user:pass@example.com", .embeddedCredentials),
            ("https://example.com?token=value", .queryNotAllowed),
            ("https://example.com#fragment", .fragmentNotAllowed),
            ("https://example.com/api/../admin", .pathTraversal),
            ("https://example.com/api/%2e%2e/admin", .pathTraversal),
        ]

        for (url, expectedError) in cases {
            XCTAssertThrowsError(try EndpointValidator.validate(
                url,
                declaredBoundary: .hosted,
                hostedAccess: .granted
            ), url) { error in
                XCTAssertEqual(error as? EndpointValidationError, expectedError)
            }
        }
    }

    func testRejectsUnsupportedOrMalformedEndpoints() {
        let endpoints = [
            "file:///tmp/provider",
            "https://",
            " https://example.com",
            "https://example.com ",
            "https://999.2.3.4",
            "https://-bad.example.com",
            "https://example.com:",
        ]

        for endpoint in endpoints {
            XCTAssertThrowsError(try EndpointValidator.validate(
                endpoint,
                declaredBoundary: .hosted,
                hostedAccess: .granted
            ), endpoint)
        }
    }

    func testExplicitPortMustBeAllowedByPolicy() throws {
        XCTAssertThrowsError(try EndpointValidator.validate(
            "http://127.0.0.1:11434",
            declaredBoundary: .localMachine
        )) { error in
            XCTAssertEqual(
                error as? EndpointValidationError,
                .portNotAllowed(port: 11_434, scheme: "http")
            )
        }

        let localProviderPolicy = EndpointValidationPolicy(
            allowedHTTPPorts: [80, 11_434]
        )
        XCTAssertNoThrow(try EndpointValidator.validate(
            "http://127.0.0.1:11434",
            declaredBoundary: .localMachine,
            policy: localProviderPolicy
        ))
    }

    func testValidatedEndpointRoundTripsThroughCodable() throws {
        let endpoint = try EndpointValidator.validate(
            "https://provider.example.com/api",
            declaredBoundary: .hosted,
            hostedAccess: .granted
        )
        let encoded = try JSONEncoder().encode(endpoint)
        let decoded = try JSONDecoder().decode(ValidatedEndpoint.self, from: encoded)
        XCTAssertEqual(decoded, endpoint)
    }
}

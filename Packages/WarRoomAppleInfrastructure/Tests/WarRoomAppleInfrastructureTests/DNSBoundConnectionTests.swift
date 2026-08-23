import Network
import XCTest
@testable import WarRoomAppleInfrastructure
import WarRoomCore

final class DNSBoundConnectionTests: XCTestCase {
    func testStrictlyClassifiesIPv4Scopes() throws {
        XCTAssertEqual(try DNSBoundIPAddress(parsing: "127.0.0.1").scope, .loopback)
        XCTAssertEqual(try DNSBoundIPAddress(parsing: "127.255.255.254").scope, .loopback)
        XCTAssertEqual(try DNSBoundIPAddress(parsing: "10.0.0.1").scope, .privateNetwork)
        XCTAssertEqual(try DNSBoundIPAddress(parsing: "172.31.255.254").scope, .privateNetwork)
        XCTAssertEqual(try DNSBoundIPAddress(parsing: "192.168.1.1").scope, .privateNetwork)
        XCTAssertEqual(try DNSBoundIPAddress(parsing: "169.254.7.8").scope, .privateNetwork)
        XCTAssertEqual(try DNSBoundIPAddress(parsing: "8.8.8.8").scope, .global)
    }

    func testRejectsInvalidAndSpecialUseIPv4() {
        let literals = [
            "", " 8.8.8.8", "01.2.3.4", "256.1.1.1", "1.2.3", "example.com",
            "0.0.0.0", "100.64.0.1", "192.0.0.1", "192.0.2.1", "192.88.99.1",
            "198.18.0.1", "198.51.100.1", "203.0.113.1", "224.0.0.1", "255.255.255.255",
        ]
        for literal in literals {
            XCTAssertThrowsError(try DNSBoundIPAddress(parsing: literal), literal)
        }
    }

    func testStrictlyClassifiesIPv6ScopesAndCanonicalizes() throws {
        XCTAssertEqual(try DNSBoundIPAddress(parsing: "::1").scope, .loopback)
        XCTAssertEqual(try DNSBoundIPAddress(parsing: "fc00::1").scope, .privateNetwork)
        XCTAssertEqual(try DNSBoundIPAddress(parsing: "fd12:3456::1").scope, .privateNetwork)
        XCTAssertEqual(try DNSBoundIPAddress(parsing: "fe80::1").scope, .privateNetwork)
        let global = try DNSBoundIPAddress(parsing: "2606:4700:4700:0000:0000:0000:0000:1111")
        XCTAssertEqual(global.scope, .global)
        XCTAssertEqual(global.literal, "2606:4700:4700::1111")
    }

    func testRejectsInvalidAndSpecialUseIPv6() {
        let literals = [
            "::", "::ffff:192.0.2.1", "fe80::1%en0", "ff02::1", "2001:db8::1",
            "3fff::1", "2001:2::1", "2001:10::1", "2001:20::1", "100::1",
            "not-an-address",
        ]
        for literal in literals {
            XCTAssertThrowsError(try DNSBoundIPAddress(parsing: literal), literal)
        }
    }

    func testPlannerAcceptsEveryAddressMatchingDeclaredBoundary() async throws {
        let endpoint = try EndpointValidator.validate(
            "https://provider.internal",
            declaredBoundary: .privateNetwork
        )
        let resolver = StubResolver(addresses: ["10.1.2.3", "192.168.5.6"])

        let plan = try await DNSBoundConnectionPlanner(resolver: resolver).plan(for: endpoint)

        XCTAssertEqual(plan.serverName, "provider.internal")
        XCTAssertEqual(plan.port, 443)
        XCTAssertEqual(plan.addresses.map(\.scope), [.privateNetwork, .privateNetwork])
        XCTAssertEqual(plan.applicationProtocols, ["http/1.1"])
        let requestedHostnames = await resolver.requestedHostnames
        XCTAssertEqual(requestedHostnames, ["provider.internal"])
    }

    func testPlannerRejectsMixedResolvedScopesBeforeConnection() async throws {
        let endpoint = try EndpointValidator.validate(
            "https://provider.internal",
            declaredBoundary: .privateNetwork
        )
        do {
            _ = try await DNSBoundConnectionPlanner(
                resolver: StubResolver(addresses: ["10.1.2.3", "8.8.8.8"])
            ).plan(for: endpoint)
            XCTFail("Expected mixed scope rejection")
        } catch {
            XCTAssertEqual(error as? DNSBoundConnectionError, .mixedAddressScopes)
        }
    }

    func testPlannerRejectsUniformBoundaryMismatch() async throws {
        let endpoint = try EndpointValidator.validate(
            "https://provider.internal",
            declaredBoundary: .privateNetwork
        )
        do {
            _ = try await DNSBoundConnectionPlanner(
                resolver: StubResolver(addresses: ["8.8.8.8", "1.1.1.1"])
            ).plan(for: endpoint)
            XCTFail("Expected boundary mismatch")
        } catch {
            XCTAssertEqual(
                error as? DNSBoundConnectionError,
                .boundaryMismatch(declared: .privateNetwork, resolved: .global)
            )
        }
    }

    func testPlannerRejectsEmptyAndDisallowedResolverAnswers() async throws {
        let endpoint = try EndpointValidator.validate(
            "https://provider.example.com",
            declaredBoundary: .hosted,
            hostedAccess: .granted
        )
        do {
            _ = try await DNSBoundConnectionPlanner(
                resolver: StubResolver(addresses: [])
            ).plan(for: endpoint)
            XCTFail("Expected empty-answer rejection")
        } catch {
            XCTAssertEqual(error as? DNSBoundConnectionError, .noResolvedAddresses)
        }

        do {
            _ = try await DNSBoundConnectionPlanner(
                resolver: StubResolver(addresses: ["203.0.113.1"])
            ).plan(for: endpoint)
            XCTFail("Expected documentation-address rejection")
        } catch {
            XCTAssertEqual(error as? DNSBoundConnectionError, .disallowedAddress)
        }
    }

    func testPlannerRejectsUnencryptedEndpoint() async throws {
        let policy = EndpointValidationPolicy(allowsPrivateNetworkHTTP: true)
        let endpoint = try EndpointValidator.validate(
            "http://provider.internal",
            declaredBoundary: .privateNetwork,
            policy: policy
        )
        do {
            _ = try await DNSBoundConnectionPlanner(
                resolver: StubResolver(addresses: ["10.0.0.1"])
            ).plan(for: endpoint)
            XCTFail("Expected HTTPS-only primitive")
        } catch {
            XCTAssertEqual(error as? DNSBoundConnectionError, .unsupportedScheme)
        }
    }

    func testConnectionUsesApprovedNumericEndpointAndRetainsLogicalName() async throws {
        let endpoint = try EndpointValidator.validate(
            "https://provider.example.com:8443",
            declaredBoundary: .hosted,
            hostedAccess: .granted,
            policy: EndpointValidationPolicy(allowedHTTPSPorts: [8443])
        )
        let plan = try await DNSBoundConnectionPlanner(
            resolver: StubResolver(addresses: ["8.8.8.8"])
        ).plan(for: endpoint)
        let address = try XCTUnwrap(plan.addresses.first)

        let connection = try plan.makeConnection(to: address)

        XCTAssertEqual(plan.serverName, "provider.example.com")
        XCTAssertEqual(plan.port, 8443)
        XCTAssertEqual(connection.endpoint, .hostPort(host: "8.8.8.8", port: 8443))
    }

    func testConnectionRejectsAddressOutsideValidatedSnapshot() async throws {
        let endpoint = try EndpointValidator.validate(
            "https://provider.example.com",
            declaredBoundary: .hosted,
            hostedAccess: .granted
        )
        let plan = try await DNSBoundConnectionPlanner(
            resolver: StubResolver(addresses: ["8.8.8.8"])
        ).plan(for: endpoint)

        XCTAssertThrowsError(
            try plan.makeConnection(to: DNSBoundIPAddress(parsing: "1.1.1.1"))
        ) { error in
            XCTAssertEqual(error as? DNSBoundConnectionError, .addressNotInValidatedSet)
        }
    }

    func testErrorsAreTypedAndRedacted() {
        let values: [DNSBoundConnectionError] = [
            .invalidHostname,
            .unsupportedScheme,
            .invalidPort,
            .resolutionFailed(code: EAI_NONAME),
            .noResolvedAddresses,
            .invalidAddressLiteral,
            .disallowedAddress,
            .mixedAddressScopes,
            .boundaryMismatch(declared: .privateNetwork, resolved: .global),
            .addressNotInValidatedSet,
        ]
        for error in values {
            let description = String(describing: error)
            XCTAssertFalse(description.contains("provider.internal"))
            XCTAssertFalse(description.contains("10.0.0.1"))
        }
    }
}

private actor StubResolver: DNSBoundAddressResolving {
    private let addresses: [String]
    private(set) var requestedHostnames: [String] = []

    init(addresses: [String]) {
        self.addresses = addresses
    }

    func resolve(hostname: String) async throws -> [String] {
        requestedHostnames.append(hostname)
        return addresses
    }
}

import XCTest
import WarRoomCore
@testable import ThoxWarRoom

@MainActor
final class WorkspaceProviderRoutingTests: XCTestCase {
    func testProviderDescriptorsAdvertiseOnlyImplementedCapabilities() {
        let openWebUI = WorkspaceProviderKind.openWebUI.descriptor
        XCTAssertEqual(openWebUI.id.rawValue, "open-webui")
        XCTAssertEqual(openWebUI.displayName, "Open WebUI")
        XCTAssertEqual(openWebUI.capabilities, [.modelCatalog])
        XCTAssertFalse(openWebUI.supports(.chatCompletions))
        XCTAssertFalse(openWebUI.supports(.streamingChat))

        let hermes = WorkspaceProviderKind.hermes.descriptor
        XCTAssertEqual(hermes.id.rawValue, "hermes-api")
        XCTAssertEqual(hermes.displayName, "Hermes Agent")
        XCTAssertEqual(hermes.capabilities, [.hermesSessions, .scopedApprovals])
        XCTAssertFalse(hermes.supports(.chatCompletions))
        XCTAssertFalse(hermes.supports(.warRoomStatus))
    }

    func testProviderPoliciesAllowOnlyDocumentedPortsAndSecurePrivateTransport() {
        let openWebUI = WorkspaceProviderKind.openWebUI.endpointPolicy
        XCTAssertEqual(openWebUI.allowedHTTPPorts, [80, 3_000, 8_080])
        XCTAssertEqual(openWebUI.allowedHTTPSPorts, [443, 8_443])
        XCTAssertFalse(openWebUI.allowsPrivateNetworkHTTP)

        let hermes = WorkspaceProviderKind.hermes.endpointPolicy
        XCTAssertEqual(hermes.allowedHTTPPorts, [80, 8_000, 8_080, 8_642])
        XCTAssertEqual(hermes.allowedHTTPSPorts, [443, 8_443])
        XCTAssertFalse(hermes.allowsPrivateNetworkHTTP)

        XCTAssertNoThrow(try EndpointValidator.validate(
            "http://localhost:8642",
            declaredBoundary: .localMachine,
            policy: hermes
        ))
        XCTAssertThrowsError(try EndpointValidator.validate(
            "http://provider.internal:8642",
            declaredBoundary: .privateNetwork,
            policy: hermes
        )) { error in
            XCTAssertEqual(error as? EndpointValidationError, .insecurePrivateNetworkTransport)
        }
    }

    func testProviderIDMappingSupportsCurrentAndLegacyProfilesOnly() {
        XCTAssertEqual(
            WorkspaceProviderKind(providerID: ProviderID(rawValue: "open-webui")),
            .openWebUI
        )
        XCTAssertEqual(
            WorkspaceProviderKind(providerID: ProviderID(rawValue: "hermes-api")),
            .hermes
        )
        XCTAssertEqual(
            WorkspaceProviderKind(providerID: ProviderID(rawValue: "workspace-provider")),
            .openWebUI
        )
        XCTAssertNil(WorkspaceProviderKind(providerID: ProviderID(rawValue: "unknown")))
        XCTAssertNil(WorkspaceProviderKind(providerID: ProviderID(rawValue: "OPEN-WEBUI")))
    }

    func testHostedCompatibilityRequiresOpenWebUIAndExactAuthorizedOrigin() throws {
        XCTAssertTrue(try profile(
            endpoint: "https://webui.thox.ai",
            provider: WorkspaceProviderKind.openWebUI.descriptor
        ).supportsHostedCompatibilityOrigin)
        XCTAssertTrue(try profile(
            endpoint: "https://webui.thox.ai",
            provider: legacyOpenWebUIDescriptor
        ).supportsHostedCompatibilityOrigin)

        XCTAssertFalse(try profile(
            endpoint: "https://webui.thox.ai",
            provider: WorkspaceProviderKind.hermes.descriptor
        ).supportsHostedCompatibilityOrigin)
        XCTAssertFalse(try profile(
            endpoint: "https://webui.thox.ai/chat",
            provider: WorkspaceProviderKind.openWebUI.descriptor
        ).supportsHostedCompatibilityOrigin)
        XCTAssertFalse(try profile(
            endpoint: "https://webui.thox.ai.evil.example",
            provider: WorkspaceProviderKind.openWebUI.descriptor
        ).supportsHostedCompatibilityOrigin)
        XCTAssertFalse(try profile(
            endpoint: "https://webui.thox.ai:8443",
            provider: WorkspaceProviderKind.openWebUI.descriptor,
            policy: WorkspaceProviderKind.openWebUI.endpointPolicy
        ).supportsHostedCompatibilityOrigin)
        XCTAssertFalse(try localProfile().supportsHostedCompatibilityOrigin)
    }

    private var legacyOpenWebUIDescriptor: ProviderDescriptor {
        ProviderDescriptor(
            id: ProviderID(rawValue: "workspace-provider"),
            displayName: "Legacy workspace provider",
            capabilities: [.modelCatalog]
        )
    }

    private func profile(
        endpoint rawEndpoint: String,
        provider: ProviderDescriptor,
        policy: EndpointValidationPolicy = .secureDefault
    ) throws -> WorkspaceProfile {
        let endpoint = try EndpointValidator.validate(
            rawEndpoint,
            declaredBoundary: .hosted,
            hostedAccess: .granted,
            policy: policy
        )
        return try WorkspaceProfile(
            displayName: "Synthetic hosted workspace",
            endpoint: endpoint,
            provider: provider
        )
    }

    private func localProfile() throws -> WorkspaceProfile {
        let endpoint = try EndpointValidator.validate(
            "http://localhost:8080",
            declaredBoundary: .localMachine,
            policy: WorkspaceProviderKind.openWebUI.endpointPolicy
        )
        return try WorkspaceProfile(
            displayName: "Synthetic local workspace",
            endpoint: endpoint,
            provider: WorkspaceProviderKind.openWebUI.descriptor
        )
    }
}

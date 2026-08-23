import XCTest
import WarRoomCore
import WarRoomHermes
import WarRoomMesh
import WarRoomOpenWebUI
@testable import ThoxWarRoom

final class WarRoomDashboardRoutingTests: XCTestCase {
    func testCanonicalProvidersRouteOnlyToTheirNativeFeature() throws {
        XCTAssertEqual(
            WorkspaceNativeFeatureRoute(profile: try profile(provider: OpenWebUIProvider.descriptor)),
            .openWebUIConnection
        )
        XCTAssertEqual(
            WorkspaceNativeFeatureRoute(profile: try profile(provider: HermesProvider.descriptor)),
            .hermesReview
        )
        XCTAssertEqual(
            WorkspaceNativeFeatureRoute(profile: try profile(provider: MeshProvider.descriptor)),
            .warRoomDashboard
        )
    }

    func testKnownProviderWithoutRequiredCapabilityDoesNotRoute() throws {
        let cases: [(ProviderDescriptor, ProviderCapability)] = [
            (OpenWebUIProvider.descriptor, .modelCatalog),
            (HermesProvider.descriptor, .hermesSessions),
            (MeshProvider.descriptor, .warRoomStatus),
        ]

        for (provider, requiredCapability) in cases {
            let stripped = ProviderDescriptor(
                id: provider.id,
                displayName: provider.displayName,
                capabilities: provider.capabilities.subtracting([requiredCapability])
            )
            XCTAssertNil(WorkspaceNativeFeatureRoute(profile: try profile(provider: stripped)))
        }
    }

    func testBorrowedCapabilityCannotRouteUnknownOrDifferentProvider() throws {
        let unknown = ProviderDescriptor(
            id: ProviderID(rawValue: "unknown-provider"),
            displayName: "Unknown",
            capabilities: [.warRoomStatus, .hermesSessions, .modelCatalog]
        )
        XCTAssertNil(WorkspaceNativeFeatureRoute(profile: try profile(provider: unknown)))

        let openWebUIWithDashboardCapability = ProviderDescriptor(
            id: OpenWebUIProvider.descriptor.id,
            displayName: OpenWebUIProvider.descriptor.displayName,
            capabilities: [.warRoomStatus]
        )
        XCTAssertNil(
            WorkspaceNativeFeatureRoute(profile: try profile(provider: openWebUIWithDashboardCapability))
        )
    }

    func testLegacyOpenWebUIProfileRetainsConnectionRoute() throws {
        let legacy = ProviderDescriptor(
            id: ProviderID(rawValue: "workspace-provider"),
            displayName: "Workspace provider",
            capabilities: []
        )
        XCTAssertEqual(
            WorkspaceNativeFeatureRoute(profile: try profile(provider: legacy)),
            .openWebUIConnection
        )
    }

    func testDashboardRouteUsesExplicitOperatorLabel() {
        XCTAssertEqual(
            WorkspaceNativeFeatureRoute.warRoomDashboard.buttonTitle,
            "Open War Room dashboard"
        )
    }

    func testDashboardSelectionRejectsInvalidMeshIdentifierWithoutFallback() throws {
        let profile = try profile(provider: MeshProvider.descriptor)

        XCTAssertNil(WarRoomDashboardRouteSelection(profile: profile, rawMeshID: ""))
        XCTAssertNil(WarRoomDashboardRouteSelection(profile: profile, rawMeshID: "not-a-uuid"))
        XCTAssertNil(WarRoomDashboardRouteSelection(
            profile: profile,
            rawMeshID: " 123e4567-e89b-12d3-a456-426614174000 "
        ))
    }

    func testDashboardSelectionRequiresDashboardRouteAndCanonicalMeshIdentifier() throws {
        let canonical = "123e4567-e89b-12d3-a456-426614174000"
        let dashboardProfile = try profile(provider: MeshProvider.descriptor)
        let selection = WarRoomDashboardRouteSelection(
            profile: dashboardProfile,
            rawMeshID: canonical
        )
        XCTAssertEqual(selection?.meshID.queryValue, canonical)

        XCTAssertNil(WarRoomDashboardRouteSelection(
            profile: try profile(provider: HermesProvider.descriptor),
            rawMeshID: canonical
        ))

        let missingCapability = ProviderDescriptor(
            id: MeshProvider.descriptor.id,
            displayName: MeshProvider.descriptor.displayName,
            capabilities: []
        )
        XCTAssertNil(WarRoomDashboardRouteSelection(
            profile: try profile(provider: missingCapability),
            rawMeshID: canonical
        ))
    }

    private func profile(provider: ProviderDescriptor) throws -> WorkspaceProfile {
        let endpoint = try EndpointValidator.validate(
            "https://mesh.internal",
            declaredBoundary: .privateNetwork
        )
        return try WorkspaceProfile(
            displayName: "Private operations",
            endpoint: endpoint,
            provider: provider
        )
    }
}

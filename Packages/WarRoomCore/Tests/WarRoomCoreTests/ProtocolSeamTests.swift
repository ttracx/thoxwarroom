import XCTest
@testable import WarRoomCore

final class ProtocolSeamTests: XCTestCase {
    func testProviderRequestAllowsOnlyRelativePaths() throws {
        XCTAssertNoThrow(try ProviderRequest(method: .get, relativePath: "/v1/models"))
        for path in [
            "v1/models",
            "//other-host/path",
            "/v1/../admin",
            "/v1/%2e%2e/admin",
            "/v1/%2F%2Fevil.example/path",
            "/v1\\..\\admin",
            "/v1?q=secret",
            "/v1#secret",
        ] {
            XCTAssertThrowsError(try ProviderRequest(method: .get, relativePath: path)) { error in
                XCTAssertEqual(error as? ProviderRequestError, .invalidRelativePath)
            }
        }
    }

    func testProviderRequestAcceptsOnlyBoundedNonSecretQueryItems() throws {
        let meshID = try ProviderQueryItem(
            name: "mesh_id",
            value: "123e4567-e89b-12d3-a456-426614174000"
        )
        let limit = try ProviderQueryItem(name: "limit", value: "100")
        let request = try ProviderRequest(
            method: .get,
            relativePath: "/api/events",
            queryItems: [meshID, limit]
        )
        XCTAssertEqual(request.queryItems, [meshID, limit])

        for (name, value) in [
            ("", "value"),
            ("token", "secret value"),
            ("redirect", "https://evil.example"),
            ("line", "one\ntwo"),
        ] {
            XCTAssertThrowsError(try ProviderQueryItem(name: name, value: value))
        }
        XCTAssertThrowsError(try ProviderRequest(
            method: .get,
            relativePath: "/api/events",
            queryItems: [limit, limit]
        )) { error in
            XCTAssertEqual(error as? ProviderRequestError, .invalidQueryItems)
        }
    }

    func testProtocolSeamsSupportInMemoryImplementations() async throws {
        let endpoint = try EndpointValidator.validate(
            "http://localhost",
            declaredBoundary: .localMachine
        )
        let provider = ProviderDescriptor(
            id: ProviderID(rawValue: "test"),
            displayName: "Test",
            capabilities: [.modelCatalog]
        )
        let profile = try WorkspaceProfile(
            displayName: "Test",
            endpoint: endpoint,
            provider: provider
        )
        let store: any WorkspaceProfileStore = InMemoryProfileStore(profile: profile)

        let storedProfile = try await store.profile(id: profile.id)
        XCTAssertEqual(storedProfile, profile)
    }
}

private actor InMemoryProfileStore: WorkspaceProfileStore {
    private var values: [WorkspaceID: WorkspaceProfile]

    init(profile: WorkspaceProfile) {
        values = [profile.id: profile]
    }

    func profiles() -> [WorkspaceProfile] {
        Array(values.values)
    }

    func profile(id: WorkspaceID) -> WorkspaceProfile? {
        values[id]
    }

    func save(_ profile: WorkspaceProfile) {
        values[profile.id] = profile
    }

    func deleteProfile(id: WorkspaceID) {
        values[id] = nil
    }
}

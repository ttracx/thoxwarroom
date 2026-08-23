import XCTest
@testable import WarRoomCore

final class WorkspaceProfileTests: XCTestCase {
    private func endpoint() throws -> ValidatedEndpoint {
        try EndpointValidator.validate(
            "http://localhost",
            declaredBoundary: .localMachine
        )
    }

    func testProfileNormalizesNameAndRoundTrips() throws {
        let createdAt = Date(timeIntervalSince1970: 100)
        let provider = ProviderDescriptor(
            id: ProviderID(rawValue: "local-openai-compatible"),
            displayName: "Local Provider",
            capabilities: [.modelCatalog, .chatCompletions, .streamingChat]
        )
        let profile = try WorkspaceProfile(
            displayName: "  Research  ",
            endpoint: endpoint(),
            provider: provider,
            createdAt: createdAt,
            updatedAt: createdAt
        )

        XCTAssertEqual(profile.displayName, "Research")
        XCTAssertTrue(profile.provider.supports(.streamingChat))
        XCTAssertFalse(profile.provider.supports(.scopedApprovals))

        let encoded = try JSONEncoder().encode(profile)
        XCTAssertEqual(try JSONDecoder().decode(WorkspaceProfile.self, from: encoded), profile)
    }

    func testRejectsInvalidNamesAndDates() throws {
        let provider = ProviderDescriptor(
            id: ProviderID(rawValue: "test"),
            displayName: "Test",
            capabilities: []
        )
        XCTAssertThrowsError(try WorkspaceProfile(
            displayName: "   ",
            endpoint: endpoint(),
            provider: provider
        )) { error in
            XCTAssertEqual(error as? WorkspaceProfileError, .emptyDisplayName)
        }
        XCTAssertThrowsError(try WorkspaceProfile(
            displayName: String(repeating: "a", count: 81),
            endpoint: endpoint(),
            provider: provider
        )) { error in
            XCTAssertEqual(error as? WorkspaceProfileError, .displayNameTooLong)
        }
        XCTAssertThrowsError(try WorkspaceProfile(
            displayName: "Research",
            endpoint: endpoint(),
            provider: provider,
            createdAt: Date(timeIntervalSince1970: 2),
            updatedAt: Date(timeIntervalSince1970: 1)
        )) { error in
            XCTAssertEqual(error as? WorkspaceProfileError, .updatedBeforeCreation)
        }
    }
}

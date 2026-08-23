import XCTest
import WarRoomCore
@testable import WarRoomHermes

final class HermesProviderTests: XCTestCase {
    func testDescriptorAdvertisesOnlyImplementedHermesCapabilities() {
        let descriptor = HermesProvider.descriptor

        XCTAssertEqual(descriptor.id, ProviderID(rawValue: "hermes-api"))
        XCTAssertEqual(descriptor.displayName, "Hermes Agent")
        XCTAssertEqual(descriptor.capabilities, [.hermesSessions, .scopedApprovals])
        XCTAssertTrue(descriptor.supports(.hermesSessions))
        XCTAssertTrue(descriptor.supports(.scopedApprovals))
        XCTAssertFalse(descriptor.supports(.chatCompletions))
        XCTAssertFalse(descriptor.supports(.modelCatalog))
        XCTAssertFalse(descriptor.supports(.warRoomStatus))
    }
}

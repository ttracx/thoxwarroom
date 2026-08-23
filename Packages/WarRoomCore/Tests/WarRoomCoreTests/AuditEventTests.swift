import XCTest
@testable import WarRoomCore

final class AuditEventTests: XCTestCase {
    func testRedactsSensitiveAndSecretNamedFieldsBeforeEncoding() throws {
        let secret = "do-not-retain"
        let event = AuditEvent(
            workspaceID: .make(),
            category: "provider",
            action: "connect",
            outcome: .succeeded,
            fields: [
                AuditField(key: "boundary", value: .string("localMachine"), privacy: .nonSensitive),
                AuditField(key: "prompt", value: .string(secret), privacy: .nonSensitive),
                AuditField(key: "model", value: .string(secret), privacy: .sensitive),
                AuditField(key: "retryCount", value: .integer(2), privacy: .nonSensitive),
            ]
        )

        XCTAssertEqual(event.metadata["boundary"], .string("localMachine"))
        XCTAssertEqual(event.metadata["prompt"], .redacted)
        XCTAssertEqual(event.metadata["model"], .redacted)
        XCTAssertEqual(event.metadata["retryCount"], .integer(2))

        let encoded = try JSONEncoder().encode(event)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains(secret))
        XCTAssertEqual(try JSONDecoder().decode(AuditEvent.self, from: encoded), event)
    }

    func testCapsNonSensitiveStringsAndDropsBlankKeys() {
        let event = AuditEvent(
            workspaceID: .make(),
            category: "test",
            action: "sanitize",
            outcome: .succeeded,
            fields: [
                AuditField(key: " ", value: .string("ignored"), privacy: .nonSensitive),
                AuditField(
                    key: "summary",
                    value: .string(String(repeating: "a", count: 300)),
                    privacy: .nonSensitive
                ),
            ]
        )

        XCTAssertNil(event.metadata[" "])
        guard case let .string(summary) = event.metadata["summary"] else {
            return XCTFail("Expected redacted string value")
        }
        XCTAssertEqual(summary.count, 256)
    }

    func testCredentialDescriptionsNeverRevealBytes() {
        let credential = ProviderCredential(bytes: Data("secret".utf8))
        XCTAssertEqual(credential.description, "<redacted>")
        XCTAssertEqual(credential.debugDescription, "ProviderCredential(<redacted>)")
        XCTAssertFalse(String(describing: credential).contains("secret"))
    }
}

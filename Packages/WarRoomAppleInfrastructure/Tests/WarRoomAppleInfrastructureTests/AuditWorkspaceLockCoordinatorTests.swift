import Foundation
import XCTest
@testable import WarRoomAppleInfrastructure
import WarRoomCore

final class AuditWorkspaceLockCoordinatorTests: XCTestCase {
    func testCreatesAbsentPrivateLockDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "thox-absent-audit-lock-tests-\(UUID().uuidString.lowercased())"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))

        _ = try AuditWorkspaceLockCoordinator(rootURL: root)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        let attributes = try FileManager.default.attributesOfItem(atPath: root.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testIndependentFileCoordinatorsContendBoundedlyAndReleaseForNextOwner() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let holder = try AuditWorkspaceLockCoordinator(
            rootURL: root,
            policy: policy(timeoutMilliseconds: 2_000),
            useProcessRegistry: false
        )
        let contender = try AuditWorkspaceLockCoordinator(
            rootURL: root,
            policy: policy(timeoutMilliseconds: 50),
            useProcessRegistry: false
        )
        let entered = expectation(description: "file lock acquired")
        let workspaceID = fixedWorkspaceID()
        let holdingTask = Task {
            try await holder.withLock(for: workspaceID) {
                entered.fulfill()
                try await Task.sleep(nanoseconds: 200_000_000)
                return true
            }
        }
        await fulfillment(of: [entered], timeout: 1)

        do {
            _ = try await contender.withLock(for: workspaceID) { true }
            XCTFail("Expected bounded file-lock contention failure")
        } catch {
            XCTAssertEqual(error as? AuditWorkspaceLockError, .acquisitionTimedOut)
            XCTAssertEqual(String(describing: error), "Audit transaction lock is unavailable.")
            XCTAssertEqual(String(reflecting: error), "AuditWorkspaceLockError(<redacted>)")
        }
        let heldValue = try await holdingTask.value
        XCTAssertTrue(heldValue)
        let nextValue = try await contender.withLock(for: workspaceID) { 7 }
        XCTAssertEqual(nextValue, 7)

        let attributes = try FileManager.default.attributesOfItem(
            atPath: root.appendingPathComponent(
                workspaceID.rawValue.uuidString.lowercased() + ".auditlock"
            ).path
        )
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testCancelledSameProcessWaiterDoesNotAcquireOrPoisonLaterAcquisition() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = try AuditWorkspaceLockCoordinator(
            rootURL: root,
            policy: policy(timeoutMilliseconds: 2_000)
        )
        let entered = expectation(description: "process lock acquired")
        let workspaceID = fixedWorkspaceID()
        let holder = Task {
            try await coordinator.withLock(for: workspaceID) {
                entered.fulfill()
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        await fulfillment(of: [entered], timeout: 1)
        let cancelledWaiter = Task {
            try await coordinator.withLock(for: workspaceID) {
                XCTFail("Cancelled waiter must not enter the critical section")
            }
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        cancelledWaiter.cancel()
        do {
            try await cancelledWaiter.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
        try await holder.value

        let acquired = try await coordinator.withLock(for: workspaceID) { "available" }
        XCTAssertEqual(acquired, "available")
    }

    func testSymbolicLinkLockFileFailsClosedWithoutFollowingTarget() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceID = fixedWorkspaceID()
        let outside = root.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString.lowercased() + ".target")
        defer { try? FileManager.default.removeItem(at: outside) }
        XCTAssertTrue(FileManager.default.createFile(atPath: outside.path, contents: Data()))
        let lockURL = root.appendingPathComponent(
            workspaceID.rawValue.uuidString.lowercased() + ".auditlock"
        )
        try FileManager.default.createSymbolicLink(at: lockURL, withDestinationURL: outside)
        let coordinator = try AuditWorkspaceLockCoordinator(rootURL: root)

        do {
            try await coordinator.withLock(for: workspaceID) {}
            XCTFail("Expected symbolic-link rejection")
        } catch {
            XCTAssertEqual(error as? AuditWorkspaceLockError, .unsafeLockPath)
        }
        XCTAssertEqual(try Data(contentsOf: outside), Data())
    }

    private func policy(timeoutMilliseconds: UInt64) -> AuditWorkspaceLockPolicy {
        AuditWorkspaceLockPolicy(
            acquisitionTimeoutNanoseconds: timeoutMilliseconds * 1_000_000,
            pollIntervalNanoseconds: 2_000_000
        )
    }

    private func fixedWorkspaceID() -> WorkspaceID {
        WorkspaceID(rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("thox-audit-lock-tests-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}

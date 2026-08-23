import Darwin
import Foundation
import WarRoomCore

/// Redacted failures from workspace audit transaction serialization.
enum AuditWorkspaceLockError: Error, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible {
    case acquisitionTimedOut
    case unsafeLockPath
    case inputOutputFailure

    var description: String { "Audit transaction lock is unavailable." }
    var debugDescription: String { "AuditWorkspaceLockError(<redacted>)" }
}

struct AuditWorkspaceLockPolicy: Equatable, Sendable {
    static let standard = AuditWorkspaceLockPolicy(
        acquisitionTimeoutNanoseconds: 15_000_000_000,
        pollIntervalNanoseconds: 10_000_000
    )

    let acquisitionTimeoutNanoseconds: UInt64
    let pollIntervalNanoseconds: UInt64

    init(acquisitionTimeoutNanoseconds: UInt64, pollIntervalNanoseconds: UInt64) {
        precondition(acquisitionTimeoutNanoseconds > 0)
        precondition(pollIntervalNanoseconds > 0)
        precondition(pollIntervalNanoseconds <= acquisitionTimeoutNanoseconds)
        self.acquisitionTimeoutNanoseconds = acquisitionTimeoutNanoseconds
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
    }
}

/// Serializes one workspace's complete ledger-and-anchor transaction.
///
/// A process-wide `NSLock` closes the same-process semantics gap between distinct
/// store actors. A persistent empty lock file plus nonblocking `flock` closes the
/// cross-process gap. Lock files are never unlinked during normal operation because
/// unlinking can let contenders lock different inodes. Descriptor closure releases
/// the kernel lock after cancellation, failure, process exit, or normal completion.
struct AuditWorkspaceLockCoordinator: Sendable {
    private let rootURL: URL?
    private let registryNamespace: String
    private let policy: AuditWorkspaceLockPolicy
    private let useProcessRegistry: Bool

    init(
        rootURL: URL,
        policy: AuditWorkspaceLockPolicy = .standard,
        useProcessRegistry: Bool = true
    ) throws {
        let standardized = rootURL.standardizedFileURL
        try SystemAtomicWorkspaceFileSystem().ensurePrivateDirectory(at: standardized)
        self.rootURL = standardized
        registryNamespace = standardized.path
        self.policy = policy
        self.useProcessRegistry = useProcessRegistry
    }

    private init(processLocalNamespace: String) {
        rootURL = nil
        registryNamespace = processLocalNamespace
        policy = .standard
        useProcessRegistry = true
    }

    static func processLocalForTesting() -> AuditWorkspaceLockCoordinator {
        AuditWorkspaceLockCoordinator(processLocalNamespace: UUID().uuidString.lowercased())
    }

    func withLock<T: Sendable>(
        for workspaceID: WorkspaceID,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        try Task.checkCancellation()
        let key = "\(registryNamespace):\(workspaceID.rawValue.uuidString.lowercased())"
        let processLock = useProcessRegistry
            ? ProcessWorkspaceLockRegistry.shared.lock(for: key)
            : nil
        if let processLock {
            try await acquire(processLock)
        }
        defer { processLock?.release() }
        try Task.checkCancellation()

        guard let rootURL else {
            return try await operation()
        }
        return try await withFileLock(at: rootURL, workspaceID: workspaceID, operation: operation)
    }

    private func acquire(_ lock: ProcessWorkspaceLock) async throws {
        let started = DispatchTime.now().uptimeNanoseconds
        while !lock.tryAcquire() {
            try Task.checkCancellation()
            if elapsedNanoseconds(since: started) >= policy.acquisitionTimeoutNanoseconds {
                throw AuditWorkspaceLockError.acquisitionTimedOut
            }
            try await Task.sleep(nanoseconds: policy.pollIntervalNanoseconds)
        }
    }

    private func withFileLock<T: Sendable>(
        at rootURL: URL,
        workspaceID: WorkspaceID,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        let directoryDescriptor = Darwin.open(
            rootURL.path,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_DIRECTORY
        )
        guard directoryDescriptor >= 0 else {
            if errno == ELOOP { throw AuditWorkspaceLockError.unsafeLockPath }
            throw AuditWorkspaceLockError.inputOutputFailure
        }
        defer { Darwin.close(directoryDescriptor) }

        let filename = workspaceID.rawValue.uuidString.lowercased() + ".auditlock"
        let descriptor = filename.withCString { pointer in
            Darwin.openat(
                directoryDescriptor,
                pointer,
                O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
                mode_t(0o600)
            )
        }
        guard descriptor >= 0 else {
            if errno == ELOOP { throw AuditWorkspaceLockError.unsafeLockPath }
            throw AuditWorkspaceLockError.inputOutputFailure
        }
        var acquired = false
        defer {
            if acquired { _ = flock(descriptor, LOCK_UN) }
            Darwin.close(descriptor)
        }

        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              status.st_nlink == 1,
              status.st_mode & S_IFMT == S_IFREG,
              Darwin.fchmod(descriptor, mode_t(0o600)) == 0 else {
            throw AuditWorkspaceLockError.unsafeLockPath
        }

        let started = DispatchTime.now().uptimeNanoseconds
        while true {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                acquired = true
                break
            }
            let failure = errno
            guard failure == EWOULDBLOCK || failure == EAGAIN else {
                throw AuditWorkspaceLockError.inputOutputFailure
            }
            try Task.checkCancellation()
            if elapsedNanoseconds(since: started) >= policy.acquisitionTimeoutNanoseconds {
                throw AuditWorkspaceLockError.acquisitionTimedOut
            }
            try await Task.sleep(nanoseconds: policy.pollIntervalNanoseconds)
        }

        try Task.checkCancellation()
        return try await operation()
    }

    private func elapsedNanoseconds(since started: UInt64) -> UInt64 {
        let now = DispatchTime.now().uptimeNanoseconds
        return now >= started ? now - started : UInt64.max
    }
}

private final class ProcessWorkspaceLock: @unchecked Sendable {
    private let lock = NSLock()

    func tryAcquire() -> Bool { lock.try() }
    func release() { lock.unlock() }
}

private final class ProcessWorkspaceLockRegistry: @unchecked Sendable {
    static let shared = ProcessWorkspaceLockRegistry()

    private let registryLock = NSLock()
    private var locks: [String: ProcessWorkspaceLock] = [:]

    func lock(for key: String) -> ProcessWorkspaceLock {
        registryLock.withLock {
            if let existing = locks[key] { return existing }
            let created = ProcessWorkspaceLock()
            locks[key] = created
            return created
        }
    }
}

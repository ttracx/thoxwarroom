import Foundation
import WarRoomCore

/// Server surface that produced a read-only snapshot.
public enum MeshSnapshotSource: String, Codable, Equatable, Sendable {
    /// User-authenticated admin-console endpoints.
    case adminConsole
}

/// Evidence strength for the captured MeshStack contract.
public enum MeshContractEvidence: String, Codable, Equatable, Sendable {
    /// DTO and route exist in current source but lack a private live capture.
    case currentSourceNotLiveVerified
}

/// Provenance retained with every read-only War Room result.
public struct MeshSnapshotMetadata: Codable, Equatable, Sendable {
    /// Mesh associated with the snapshot.
    public let meshID: MeshID
    /// Local time when decoding and contract validation completed.
    public let fetchedAt: Date
    /// Server surface that produced the data.
    public let source: MeshSnapshotSource
    /// Strength of evidence supporting the wire contract.
    public let evidence: MeshContractEvidence
    /// Validated workspace network boundary used for the request.
    public let networkBoundary: NetworkBoundary

    /// Creates immutable snapshot provenance.
    public init(
        meshID: MeshID,
        fetchedAt: Date,
        source: MeshSnapshotSource,
        evidence: MeshContractEvidence,
        networkBoundary: NetworkBoundary
    ) {
        self.meshID = meshID
        self.fetchedAt = fetchedAt
        self.source = source
        self.evidence = evidence
        self.networkBoundary = networkBoundary
    }

    /// Non-negative age, treating future timestamps within clock skew as zero.
    public func age(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(fetchedAt))
    }

    /// Classifies freshness without mutating or refreshing the snapshot.
    public func freshness(
        at now: Date,
        policy: MeshStalenessPolicy
    ) -> MeshSnapshotFreshness {
        let futureOffset = fetchedAt.timeIntervalSince(now)
        if futureOffset > policy.allowedFutureClockSkew {
            return .futureDated
        }
        return age(at: now) > policy.maximumAge ? .stale : .fresh
    }
}

/// A typed read-only value paired with local capture provenance.
public struct MeshSnapshot<Value: Sendable>: Sendable {
    /// Decoded, contract-validated read-only value.
    public let value: Value
    /// Capture provenance and freshness inputs.
    public let metadata: MeshSnapshotMetadata

    /// Pairs a read-only value with its provenance.
    public init(value: Value, metadata: MeshSnapshotMetadata) {
        self.value = value
        self.metadata = metadata
    }
}

extension MeshSnapshot: Equatable where Value: Equatable {}

/// Local policy used to classify snapshot staleness.
public struct MeshStalenessPolicy: Equatable, Sendable {
    /// Age after which a snapshot is stale.
    public let maximumAge: TimeInterval
    /// Future clock offset tolerated before flagging a snapshot.
    public let allowedFutureClockSkew: TimeInterval

    /// Creates a finite, non-negative staleness policy.
    public init(
        maximumAge: TimeInterval,
        allowedFutureClockSkew: TimeInterval = 5
    ) throws {
        guard maximumAge.isFinite,
              maximumAge >= 0,
              allowedFutureClockSkew.isFinite,
              allowedFutureClockSkew >= 0 else {
            throw MeshStalenessPolicyError.invalidDuration
        }
        self.maximumAge = maximumAge
        self.allowedFutureClockSkew = allowedFutureClockSkew
    }

    /// Thirty-second freshness with five seconds of tolerated clock skew.
    public static let operational = MeshStalenessPolicy(
        validatedMaximumAge: 30,
        validatedAllowedFutureClockSkew: 5
    )

    private init(
        validatedMaximumAge: TimeInterval,
        validatedAllowedFutureClockSkew: TimeInterval
    ) {
        maximumAge = validatedMaximumAge
        allowedFutureClockSkew = validatedAllowedFutureClockSkew
    }
}

/// Invalid local staleness policy.
public enum MeshStalenessPolicyError: Error, Equatable, Sendable {
    /// A duration was negative or non-finite.
    case invalidDuration
}

/// Freshness state computed solely from local metadata and policy.
public enum MeshSnapshotFreshness: String, Codable, Equatable, Sendable {
    /// Snapshot falls within the accepted age and clock-skew windows.
    case fresh
    /// Snapshot is older than the policy maximum.
    case stale
    /// Snapshot capture time exceeds allowed future clock skew.
    case futureDated
}

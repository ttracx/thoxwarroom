import Foundation
import WarRoomCore
import WarRoomMesh

enum WarRoomDashboardSection: String, CaseIterable, Equatable, Sendable {
    case devices
    case topology
    case events

    var title: String {
        rawValue.capitalized
    }
}

enum WarRoomDashboardFailureReason: Hashable, Sendable {
    case offline
    case authenticationRequired
    case accessDenied
    case unavailable
    case invalidResponse
}

struct WarRoomDashboardSectionFailure: Equatable, Sendable {
    let section: WarRoomDashboardSection
    let reason: WarRoomDashboardFailureReason

    var message: String {
        switch reason {
        case .offline:
            "The section could not reach the configured provider."
        case .authenticationRequired:
            "The stored credential was not accepted for this section."
        case .accessDenied:
            "The stored credential cannot access this section."
        case .unavailable:
            "The section is unavailable from the configured provider."
        case .invalidResponse:
            "The section returned data that could not be verified."
        }
    }
}

struct WarRoomDashboardSnapshot: Equatable, Sendable {
    let devices: [MeshDevice]
    let topology: MeshTopology?
    let events: [MeshEvent]
    let provenance: [MeshSnapshotMetadata]
    let failures: [WarRoomDashboardSectionFailure]

    var isEmpty: Bool {
        devices.isEmpty && (topology?.nodes.isEmpty ?? true) && events.isEmpty
    }

    func isStale(at date: Date, policy: MeshStalenessPolicy) -> Bool {
        provenance.contains { $0.freshness(at: date, policy: policy) != .fresh }
    }
}

enum WarRoomDashboardServiceError: Error, Equatable, Sendable {
    case unsupportedProvider
    case credentialRequired
    case credentialStoreUnavailable
    case providerOffline
    case authenticationRequired
    case accessDenied
    case unavailable
}

extension WarRoomDashboardServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            "This workspace provider does not advertise read-only War Room status support."
        case .credentialRequired:
            "Add a workspace credential before loading protected War Room status."
        case .credentialStoreUnavailable:
            "Secure credential storage is unavailable on this device."
        case .providerOffline:
            "The configured provider is unreachable. Check its network and service status."
        case .authenticationRequired:
            "The stored workspace credential was not accepted."
        case .accessDenied:
            "The stored workspace credential cannot access this War Room."
        case .unavailable:
            "War Room status is unavailable. No sensitive identifiers were retained in this error."
        }
    }
}

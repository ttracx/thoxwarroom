import Foundation
import WarRoomCore
import WarRoomMesh

@MainActor
final class WarRoomDashboardModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case empty(WarRoomDashboardSnapshot)
        case ready(WarRoomDashboardSnapshot)
        case stale(WarRoomDashboardSnapshot)
        case partialFailure(WarRoomDashboardSnapshot)
        case offline(String)
        case error(String)
    }

    @Published private(set) var state: State = .idle

    let profile: WorkspaceProfile
    private let meshID: MeshID
    private let service: any WarRoomDashboardServicing
    private let stalenessPolicy: MeshStalenessPolicy
    private let now: @Sendable () -> Date
    private var operation: Task<Void, Never>?
    private var generation = 0

    init(
        profile: WorkspaceProfile,
        meshID: MeshID,
        service: any WarRoomDashboardServicing = DefaultWarRoomDashboardService(),
        stalenessPolicy: MeshStalenessPolicy = .operational,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.profile = profile
        self.meshID = meshID
        self.service = service
        self.stalenessPolicy = stalenessPolicy
        self.now = now
    }

    deinit {
        operation?.cancel()
    }

    func load() {
        operation?.cancel()
        generation += 1
        let activeGeneration = generation
        state = .loading
        let profile = profile
        let meshID = meshID
        let service = service
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await service.loadDashboard(for: profile, meshID: meshID)
                try Task.checkCancellation()
                guard generation == activeGeneration else { return }
                state = state(for: snapshot)
                operation = nil
            } catch is CancellationError {
                guard generation == activeGeneration else { return }
                state = .idle
                operation = nil
            } catch {
                guard generation == activeGeneration else { return }
                state = Self.failureState(for: error)
                operation = nil
            }
        }
    }

    func cancel() {
        generation += 1
        operation?.cancel()
        operation = nil
        if state == .loading {
            state = .idle
        }
    }

    func waitForCurrentLoad() async {
        await operation?.value
    }

    private func state(for snapshot: WarRoomDashboardSnapshot) -> State {
        if !snapshot.failures.isEmpty { return .partialFailure(snapshot) }
        if snapshot.isEmpty { return .empty(snapshot) }
        if snapshot.isStale(at: now(), policy: stalenessPolicy) { return .stale(snapshot) }
        return .ready(snapshot)
    }

    private static func failureState(for error: Error) -> State {
        guard let serviceError = error as? WarRoomDashboardServiceError else {
            return .error("War Room status could not be loaded. No sensitive identifiers were retained.")
        }
        let message = serviceError.localizedDescription
        return serviceError == .providerOffline ? .offline(message) : .error(message)
    }
}

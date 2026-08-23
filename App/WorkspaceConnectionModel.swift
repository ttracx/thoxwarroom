import Foundation
import WarRoomCore
import WarRoomOpenWebUI

@MainActor
final class WorkspaceConnectionModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case credentialRequired(WorkspaceConnectionProvenance)
        case empty(WorkspaceConnectionProvenance)
        case success(WorkspaceConnectionProvenance, [OpenWebUIModel])
        case offline(String)
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published var credentialEntry = ""
    @Published private(set) var credentialMessage: String?

    let profile: WorkspaceProfile
    private let service: any WorkspaceConnectionServicing
    private var operation: Task<Void, Never>?
    private var generation = 0

    init(
        profile: WorkspaceProfile,
        service: any WorkspaceConnectionServicing
    ) {
        self.profile = profile
        self.service = service
    }

    func connect() {
        operation?.cancel()
        generation += 1
        let activeGeneration = generation
        credentialMessage = nil
        state = .loading
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let provenance = try await service.testPublicConnection(for: profile)
                try Task.checkCancellation()
                guard try await service.hasCredential(for: profile.id) else {
                    guard activeGeneration == generation else { return }
                    state = .credentialRequired(provenance)
                    operation = nil
                    return
                }
                let models = try await service.protectedModels(for: profile)
                try Task.checkCancellation()
                guard activeGeneration == generation else { return }
                state = models.isEmpty
                    ? .empty(provenance)
                    : .success(provenance, models)
                operation = nil
            } catch is CancellationError {
                guard activeGeneration == generation else { return }
                operation = nil
            } catch {
                guard activeGeneration == generation else { return }
                state = stateForError(error)
                operation = nil
            }
        }
    }

    func cancel() {
        generation += 1
        operation?.cancel()
        operation = nil
        credentialEntry = ""
        if state == .loading {
            state = .idle
        }
    }

    func saveCredential() {
        let submittedCredential = credentialEntry
        credentialMessage = nil
        operation?.cancel()
        generation += 1
        let activeGeneration = generation
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.storeCredential(submittedCredential, for: profile.id)
                try Task.checkCancellation()
                guard activeGeneration == generation else { return }
                credentialEntry = ""
                operation = nil
                connect()
            } catch is CancellationError {
                guard activeGeneration == generation else { return }
                operation = nil
            } catch {
                guard activeGeneration == generation else { return }
                credentialEntry = ""
                credentialMessage = nonSensitiveMessage(for: error)
                operation = nil
            }
        }
    }

    func removeCredential() {
        operation?.cancel()
        generation += 1
        let activeGeneration = generation
        credentialEntry = ""
        credentialMessage = nil
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.removeCredential(for: profile.id)
                try Task.checkCancellation()
                guard activeGeneration == generation else { return }
                operation = nil
                connect()
            } catch is CancellationError {
                guard activeGeneration == generation else { return }
                operation = nil
            } catch {
                guard activeGeneration == generation else { return }
                state = .error(nonSensitiveMessage(for: error))
                operation = nil
            }
        }
    }

    func waitForCurrentOperation() async {
        var observedGeneration = -1
        while let activeOperation = operation, observedGeneration != generation {
            observedGeneration = generation
            await activeOperation.value
        }
    }

    var canRefresh: Bool {
        operation == nil && state != .loading
    }

    private func stateForError(_ error: Error) -> State {
        if error as? WorkspaceConnectionServiceError == .providerOffline {
            return .offline(nonSensitiveMessage(for: error))
        }
        return .error(nonSensitiveMessage(for: error))
    }

    private func nonSensitiveMessage(for error: Error) -> String {
        if let connectionError = error as? WorkspaceConnectionServiceError {
            return connectionError.localizedDescription
        }
        return "The workspace connection could not be completed. No sensitive details were retained."
    }
}

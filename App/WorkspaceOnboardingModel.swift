import Foundation
import WarRoomCore

@MainActor
final class WorkspaceOnboardingModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case empty
        case editing
        case saving
        case ready(WorkspaceProfile)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published var draft = WorkspaceDraft()
    @Published private(set) var validationMessage: String?
    @Published private(set) var configurations: [WorkspaceProfile] = []

    private let service: any WorkspaceOnboardingServicing

    init(service: any WorkspaceOnboardingServicing) {
        self.service = service
    }

    func load() async {
        phase = .loading
        do {
            configurations = try await service.loadConfigurations()
            phase = configurations.first.map(Phase.ready) ?? .empty
        } catch is CancellationError {
            return
        } catch {
            configurations = []
            phase = .failed(nonSensitiveMessage(for: error))
        }
    }

    func beginConfiguration() {
        draft = WorkspaceDraft()
        validationMessage = nil
        phase = .editing
    }

    func cancelConfiguration() {
        validationMessage = nil
        draft = WorkspaceDraft()
        phase = configurations.first.map(Phase.ready) ?? .empty
    }

    func selectBoundary(_ boundary: NetworkBoundary) {
        draft.boundary = boundary
        if boundary != .hosted { draft.hasHostedDataTransferConsent = false }
        validationMessage = nil
    }

    func save(draft submittedDraft: WorkspaceDraft? = nil) async {
        guard phase == .editing else { return }
        if let submittedDraft {
            draft = submittedDraft
        }
        validationMessage = nil
        phase = .saving
        do {
            let saved = try await service.saveConfiguration(from: draft)
            configurations = try await service.loadConfigurations()
            guard configurations.first?.id == saved.id else {
                throw WorkspaceOnboardingError.persistence
            }
            draft = WorkspaceDraft()
            phase = .ready(saved)
        } catch is CancellationError {
            phase = .editing
        } catch {
            validationMessage = nonSensitiveMessage(for: error)
            phase = .editing
        }
    }

    func selectConfiguration(_ workspaceID: WorkspaceID) async {
        guard !phase.isBusy, configurations.contains(where: { $0.id == workspaceID }) else {
            return
        }
        phase = .loading
        do {
            let selected = try await service.selectConfiguration(workspaceID)
            configurations = try await service.loadConfigurations()
            guard configurations.first?.id == selected.id else {
                throw WorkspaceOnboardingError.persistence
            }
            phase = .ready(selected)
        } catch is CancellationError {
            phase = configurations.first.map(Phase.ready) ?? .empty
        } catch {
            phase = .failed(nonSensitiveMessage(for: error))
        }
    }

    func reset() async {
        do {
            try await service.deleteConfiguration()
            draft = WorkspaceDraft()
            validationMessage = nil
            configurations = try await service.loadConfigurations()
            phase = configurations.first.map(Phase.ready) ?? .empty
        } catch {
            phase = .failed(nonSensitiveMessage(for: error))
        }
    }

    private func nonSensitiveMessage(for error: Error) -> String {
        if let onboardingError = error as? WorkspaceOnboardingError {
            return onboardingError.localizedDescription
        }
        return "Workspace configuration is unavailable. No connection was attempted."
    }
}

private extension WorkspaceOnboardingModel.Phase {
    var isBusy: Bool {
        switch self {
        case .loading, .saving: true
        case .empty, .editing, .ready, .failed: false
        }
    }
}

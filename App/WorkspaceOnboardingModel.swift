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

    private let service: any WorkspaceOnboardingServicing

    init(service: any WorkspaceOnboardingServicing) {
        self.service = service
    }

    func load() async {
        phase = .loading
        do {
            phase = if let configuration = try await service.loadConfiguration() {
                .ready(configuration)
            } else {
                .empty
            }
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(nonSensitiveMessage(for: error))
        }
    }

    func beginConfiguration() {
        validationMessage = nil
        phase = .editing
    }

    func selectBoundary(_ boundary: NetworkBoundary) {
        draft.boundary = boundary
        if boundary != .hosted { draft.hasHostedDataTransferConsent = false }
        validationMessage = nil
    }

    func save() async {
        guard phase == .editing else { return }
        validationMessage = nil
        phase = .saving
        do {
            phase = .ready(try await service.saveConfiguration(from: draft))
        } catch is CancellationError {
            phase = .editing
        } catch {
            validationMessage = nonSensitiveMessage(for: error)
            phase = .editing
        }
    }

    func reset() async {
        do {
            try await service.deleteConfiguration()
            draft = WorkspaceDraft()
            validationMessage = nil
            phase = .empty
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

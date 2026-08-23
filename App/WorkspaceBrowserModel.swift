import Foundation
import WarRoomAppleInfrastructure

protocol WorkspaceBrowserServicing: Sendable {
    var rootDisplayPath: String { get }
    func list(relativePath: String) async throws -> WorkspaceBrowserDirectory
    func preview(relativePath: String) async throws -> WorkspaceTextPreview
}

actor DefaultWorkspaceBrowserService: WorkspaceBrowserServicing {
    nonisolated let rootDisplayPath: String
    private let browser: ConfinedWorkspaceBrowser

    init(rootURL: URL) throws {
        let browser = try ConfinedWorkspaceBrowser(rootURL: rootURL)
        self.browser = browser
        self.rootDisplayPath = browser.rootDisplayPath
    }

    func list(relativePath: String) async throws -> WorkspaceBrowserDirectory {
        try browser.list(relativePath: relativePath)
    }

    func preview(relativePath: String) async throws -> WorkspaceTextPreview {
        try browser.preview(relativePath: relativePath)
    }
}

@MainActor
final class WorkspaceBrowserModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case directory(WorkspaceBrowserDirectory)
        case loadingPreview(WorkspaceBrowserDirectory)
        case preview(WorkspaceTextPreview, directory: WorkspaceBrowserDirectory)
        case failed(String, lastDirectory: WorkspaceBrowserDirectory?)
    }

    @Published private(set) var phase: Phase = .loading
    let rootDisplayPath: String

    private let service: any WorkspaceBrowserServicing
    private var task: Task<Void, Never>?
    private var generation = 0
    private var currentDirectory: WorkspaceBrowserDirectory?

    init(service: any WorkspaceBrowserServicing) {
        self.service = service
        self.rootDisplayPath = service.rootDisplayPath
    }

    deinit { task?.cancel() }

    func loadRoot() {
        loadDirectory(relativePath: "")
    }

    func open(_ entry: WorkspaceBrowserEntry) {
        switch entry.kind {
        case .directory:
            loadDirectory(relativePath: entry.relativePath)
        case .file:
            loadPreview(relativePath: entry.relativePath)
        case .symbolicLinkBlocked:
            phase = .failed(
                "This symbolic link is blocked because it could leave the selected root.",
                lastDirectory: currentDirectory
            )
        case .unsupported:
            phase = .failed(
                "This item type is unavailable in the read-only text browser.",
                lastDirectory: currentDirectory
            )
        }
    }

    func goToParent() {
        guard let directory = currentDirectory, !directory.relativePath.isEmpty else { return }
        var components = directory.relativePath.split(separator: "/").map(String.init)
        components.removeLast()
        loadDirectory(relativePath: components.joined(separator: "/"))
    }

    func closePreview() {
        guard let currentDirectory else { return }
        phase = .directory(currentDirectory)
    }

    func recover() {
        if let currentDirectory {
            phase = .directory(currentDirectory)
        } else {
            loadRoot()
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
    }

    func waitForCurrentOperation() async {
        await task?.value
    }

    private func loadDirectory(relativePath: String) {
        beginOperation()
        let activeGeneration = generation
        phase = .loading
        let service = service
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let directory = try await service.list(relativePath: relativePath)
                try Task.checkCancellation()
                guard generation == activeGeneration else { return }
                currentDirectory = directory
                phase = .directory(directory)
                task = nil
            } catch is CancellationError {
                return
            } catch {
                guard generation == activeGeneration else { return }
                phase = .failed(Self.safeMessage(for: error), lastDirectory: currentDirectory)
                task = nil
            }
        }
    }

    private func loadPreview(relativePath: String) {
        guard let directory = currentDirectory else { return }
        beginOperation()
        let activeGeneration = generation
        phase = .loadingPreview(directory)
        let service = service
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let preview = try await service.preview(relativePath: relativePath)
                try Task.checkCancellation()
                guard generation == activeGeneration else { return }
                phase = .preview(preview, directory: directory)
                task = nil
            } catch is CancellationError {
                return
            } catch {
                guard generation == activeGeneration else { return }
                phase = .failed(Self.safeMessage(for: error), lastDirectory: directory)
                task = nil
            }
        }
    }

    private func beginOperation() {
        generation += 1
        task?.cancel()
        task = nil
    }

    private static func safeMessage(for error: Error) -> String {
        guard let browserError = error as? WorkspaceBrowserError else {
            return "The selected local item could not be read. No file content was retained."
        }
        switch browserError {
        case .previewTooLarge(let limit):
            return "This file exceeds the \(limit)-byte local preview limit."
        case .notText:
            return "This file is not safe UTF-8 text, so no preview was retained."
        case .symbolicLinkBlocked, .invalidRelativePath:
            return "This path is blocked because it could leave the selected root."
        case .notDirectory, .notRegularFile, .itemUnavailable:
            return "This local item is unavailable or its type changed."
        case .invalidRoot:
            return "The selected root is no longer available. Choose it again."
        case .invalidLimits, .readFailed:
            return "The local read-only browser could not safely read this item."
        }
    }
}

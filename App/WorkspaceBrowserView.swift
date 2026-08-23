import SwiftUI
import UniformTypeIdentifiers
import WarRoomAppleInfrastructure
import WarRoomCore

struct WorkspaceBrowserHost: View {
    let profile: WorkspaceProfile
    let onClose: () -> Void

    @State private var model: WorkspaceBrowserModel?
    @State private var isRootPickerPresented = false
    @State private var selectionError: String?

    var body: some View {
        NavigationStack {
            Group {
                if !profile.supportsLocalWorkspaceBrowser {
                    stateCard(
                        icon: "hand.raised.slash",
                        title: "Local browser unavailable",
                        detail: "Choose a local-device workspace before selecting a filesystem root."
                    )
                } else if let model {
                    WorkspaceBrowserView(model: model)
                } else {
                    rootSelection
                }
            }
            .navigationTitle("Local workspace browser")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Workspace", action: onClose)
                }
                if model != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Choose another root") { isRootPickerPresented = true }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isRootPickerPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleSelection
        )
        .alert(
            "Root unavailable",
            isPresented: Binding(
                get: { model != nil && selectionError != nil },
                set: { if !$0 { selectionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { selectionError = nil }
        } message: {
            Text(selectionError ?? "The selected root is unavailable.")
        }
        .onDisappear { model?.cancel() }
        .workspaceReturnCommand(WorkspaceCommandAction("Return to Workspace", perform: onClose))
    }

    private var rootSelection: some View {
        VStack(spacing: 16) {
            stateCard(
                icon: "folder.badge.plus",
                title: "Choose a local root",
                detail: "Only the folder you select and its non-symlink descendants can be listed. The selection is not uploaded or saved by this browser."
            )
            Button("Choose Folder") { isRootPickerPresented = true }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("choose-workspace-root")
            if let selectionError {
                Label(selectionError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("workspace-root-error")
            }
        }
        .padding(24)
    }

    private func stateCard(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 38))
                .foregroundStyle(ThoxTheme.accent)
                .accessibilityHidden(true)
            Text(title).font(.title2.weight(.semibold))
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: 560)
        .padding(28)
        .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(ThoxTheme.separator) }
    }

    private func handleSelection(_ result: Result<[URL], Error>) {
        do {
            guard let rootURL = try result.get().first else { return }
            let service = try DefaultWorkspaceBrowserService(rootURL: rootURL)
            let newModel = WorkspaceBrowserModel(service: service)
            model?.cancel()
            model = newModel
            selectionError = nil
            newModel.loadRoot()
        } catch let error as CocoaError where error.code == .userCancelled {
            return
        } catch is CancellationError {
            return
        } catch {
            selectionError = "The selected folder could not be opened as a confined read-only root."
        }
    }
}

struct WorkspaceBrowserView: View {
    @ObservedObject var model: WorkspaceBrowserModel

    var body: some View {
        ZStack {
            ThoxTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    provenance
                    phaseContent
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding()
            }
        }
        .tint(ThoxTheme.accent)
        .accessibilityIdentifier("workspace-browser")
        .workspaceRefreshCommand(browserRefreshCommand)
    }

    private var browserRefreshCommand: WorkspaceCommandAction? {
        guard model.canRefresh else { return nil }
        return WorkspaceCommandAction("Refresh Local Folder") { model.refreshCurrentDirectory() }
    }

    private var provenance: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Operator-selected local root", systemImage: "lock.open.display")
                .font(.headline)
            Text(model.rootDisplayPath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .privacySensitive()
                .accessibilityIdentifier("workspace-browser-root")
            Text("Read-only • No uploads • No provider or network request")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ThoxTheme.accent)
        }
        .padding(16)
        .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(ThoxTheme.separator) }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch model.phase {
        case .loading:
            stateCard(title: "Loading folder…", detail: "Reading bounded local metadata only") {
                ProgressView()
            }
            .accessibilityIdentifier("workspace-browser-loading")
        case .directory(let directory):
            directoryContent(directory)
        case .loadingPreview(let directory):
            VStack(alignment: .leading, spacing: 12) {
                directoryHeader(directory)
                stateCard(title: "Loading text preview…", detail: "Reading a bounded local file") {
                    ProgressView()
                }
            }
            .accessibilityIdentifier("workspace-preview-loading")
        case .preview(let preview, let directory):
            previewContent(preview, directory: directory)
        case .failed(let message, let lastDirectory):
            VStack(alignment: .leading, spacing: 12) {
                stateCard(title: "Local item unavailable", detail: message) {
                    Button(lastDirectory == nil ? "Try root again" : "Back to folder") {
                        model.recover()
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let lastDirectory { directoryHeader(lastDirectory) }
            }
            .accessibilityIdentifier("workspace-browser-error")
        }
    }

    private func directoryContent(_ directory: WorkspaceBrowserDirectory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            directoryHeader(directory)
            if directory.isTruncated {
                Label("This folder exceeds the local listing limit. Only a bounded subset is shown.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("workspace-browser-truncated")
            }
            if directory.entries.isEmpty {
                stateCard(title: "Folder is empty", detail: "No local items were found inside this root.") {
                    EmptyView()
                }
                .accessibilityIdentifier("workspace-browser-empty")
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(directory.entries) { entry in
                        Button { model.open(entry) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: icon(for: entry.kind))
                                    .frame(width: 24)
                                    .foregroundStyle(color(for: entry.kind))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.name).lineLimit(1)
                                    Text(detail(for: entry))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if entry.kind == .directory || entry.kind == .file {
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                        .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay { RoundedRectangle(cornerRadius: 10).stroke(ThoxTheme.separator) }
                        .accessibilityIdentifier("workspace-entry-\(entry.id)")
                    }
                }
            }
        }
    }

    private func directoryHeader(_ directory: WorkspaceBrowserDirectory) -> some View {
        HStack {
            Button("Up", systemImage: "chevron.left") { model.goToParent() }
                .disabled(directory.relativePath.isEmpty)
                .accessibilityIdentifier("workspace-browser-up")
            Text(directory.relativePath.isEmpty ? "Root" : directory.relativePath)
                .font(.headline.monospaced())
                .lineLimit(1)
                .privacySensitive()
            Spacer()
            Text("\(directory.entries.count) items").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func previewContent(
        _ preview: WorkspaceTextPreview,
        directory: WorkspaceBrowserDirectory
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Folder", systemImage: "chevron.left") { model.closePreview() }
                Text(preview.relativePath).font(.headline.monospaced()).lineLimit(1).privacySensitive()
                Spacer()
                Text("\(preview.byteCount) bytes").font(.caption).foregroundStyle(.secondary)
            }
            Text("Source: \(directory.relativePath.isEmpty ? "selected root" : directory.relativePath) • Local UTF-8 text")
                .font(.caption)
                .foregroundStyle(.secondary)
                .privacySensitive()
            Text(preview.text)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .privacySensitive()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(ThoxTheme.separator) }
                .accessibilityIdentifier("workspace-text-preview")
        }
    }

    private func stateCard<Actions: View>(
        title: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 12) {
            Text(title).font(.title3.weight(.semibold))
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
            actions()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(ThoxTheme.separator) }
    }

    private func icon(for kind: WorkspaceBrowserEntryKind) -> String {
        switch kind {
        case .directory: "folder.fill"
        case .file: "doc.text"
        case .symbolicLinkBlocked: "link.badge.plus"
        case .unsupported: "questionmark.square.dashed"
        }
    }

    private func color(for kind: WorkspaceBrowserEntryKind) -> Color {
        switch kind {
        case .directory, .file: ThoxTheme.accent
        case .symbolicLinkBlocked: .orange
        case .unsupported: .secondary
        }
    }

    private func detail(for entry: WorkspaceBrowserEntry) -> String {
        switch entry.kind {
        case .directory: "Folder inside selected root"
        case .file:
            entry.byteCount.map { "Read-only preview candidate • \($0) bytes" } ?? "Read-only preview candidate"
        case .symbolicLinkBlocked: "Symbolic link blocked"
        case .unsupported: "Unsupported local item type"
        }
    }
}

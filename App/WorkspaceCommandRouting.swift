import SwiftUI

@MainActor
struct WorkspaceCommandAction {
    let title: String
    let perform: @MainActor () -> Void

    init(_ title: String, perform: @escaping @MainActor () -> Void) {
        self.title = title
        self.perform = perform
    }
}

#if os(macOS)
private struct ReturnToWorkspaceCommandKey: FocusedValueKey {
    typealias Value = WorkspaceCommandAction
}

private struct RefreshFeatureCommandKey: FocusedValueKey {
    typealias Value = WorkspaceCommandAction
}

private struct OpenFeatureInBrowserCommandKey: FocusedValueKey {
    typealias Value = WorkspaceCommandAction
}

extension FocusedValues {
    var returnToWorkspaceCommand: WorkspaceCommandAction? {
        get { self[ReturnToWorkspaceCommandKey.self] }
        set { self[ReturnToWorkspaceCommandKey.self] = newValue }
    }

    var refreshFeatureCommand: WorkspaceCommandAction? {
        get { self[RefreshFeatureCommandKey.self] }
        set { self[RefreshFeatureCommandKey.self] = newValue }
    }

    var openFeatureInBrowserCommand: WorkspaceCommandAction? {
        get { self[OpenFeatureInBrowserCommandKey.self] }
        set { self[OpenFeatureInBrowserCommandKey.self] = newValue }
    }
}

struct WorkspaceFeatureCommands: Commands {
    @FocusedValue(\.returnToWorkspaceCommand) private var returnToWorkspace
    @FocusedValue(\.refreshFeatureCommand) private var refreshFeature
    @FocusedValue(\.openFeatureInBrowserCommand) private var openInBrowser

    var body: some Commands {
        CommandMenu("Workspace") {
            Button(returnToWorkspace?.title ?? "Return to Workspace") {
                returnToWorkspace?.perform()
            }
            .keyboardShortcut("1", modifiers: [.command])
            .disabled(returnToWorkspace == nil)

            Divider()

            Button(refreshFeature?.title ?? "Refresh Visible Feature") {
                refreshFeature?.perform()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(refreshFeature == nil)

            Button(openInBrowser?.title ?? "Open Visible Page in Browser") {
                openInBrowser?.perform()
            }
            .keyboardShortcut("b", modifiers: [.command])
            .disabled(openInBrowser == nil)
        }
    }
}
#endif

extension View {
    @ViewBuilder
    func workspaceReturnCommand(_ action: WorkspaceCommandAction?) -> some View {
        #if os(macOS)
        focusedSceneValue(\.returnToWorkspaceCommand, action)
        #else
        self
        #endif
    }

    @ViewBuilder
    func workspaceRefreshCommand(_ action: WorkspaceCommandAction?) -> some View {
        #if os(macOS)
        focusedSceneValue(\.refreshFeatureCommand, action)
        #else
        self
        #endif
    }

    @ViewBuilder
    func workspaceOpenInBrowserCommand(_ action: WorkspaceCommandAction?) -> some View {
        #if os(macOS)
        focusedSceneValue(\.openFeatureInBrowserCommand, action)
        #else
        self
        #endif
    }
}

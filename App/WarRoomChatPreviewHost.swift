// WarRoomChatPreviewHost.swift
// NavigationStack host for the chat preview. Owns the `WarRoomChatPreviewModel`
// so the surface follows the same lifecycle pattern as the other workspace
// features (Provider connection, Hermes review, War Room dashboard).

import SwiftUI
import WarRoomCore

struct WarRoomChatPreviewHost: View {
    @StateObject private var model: WarRoomChatPreviewModel
    let onClose: () -> Void

    init(profile: WorkspaceProfile, onClose: @escaping () -> Void) {
        _model = StateObject(wrappedValue: WarRoomChatPreviewModel(
            workspaceLabel: profile.displayName,
            boundaryLabel: profile.endpoint.boundary.title
        ))
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            WarRoomChatPreviewView(model: model)
                .toolbar { closeButton }
        }
        .tint(ThoxTheme.accent)
        .workspaceReturnCommand(WorkspaceCommandAction("Return to Workspace", perform: onClose))
        .workspaceRefreshCommand(WorkspaceCommandAction("Restore Golden Fixture") {
            model.restoreGolden()
        })
    }

    @ToolbarContentBuilder
    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Workspace", action: onClose)
        }
    }
}

// WarRoomChatPreviewView.swift
// Top-level chat surface. Ports the golden reference layout (menubar strip,
// scrolling transcript, artifact side-panel + fullscreen overlay) into
// SwiftUI. The composer is intentionally rendered in a "preview" mode until
// `OpenWebUIProvider.nativeChatContract.isAvailable` flips true — see the
// header banner and the disabled Send affordance.

import SwiftUI
import WarRoomCore
import WarRoomOpenWebUI

struct WarRoomChatPreviewView: View {
    @ObservedObject var model: WarRoomChatPreviewModel

    @State private var activeArtifact: ArtifactSpec?
    @State private var artifactTab: ArtifactPanelTab = .preview
    @State private var fullscreenArtifact: ArtifactSpec?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ThoxTheme.background.ignoresSafeArea()

            content
        }
        .navigationTitle("Chat preview")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $fullscreenArtifact) { spec in
            ArtifactFullscreenSheet(spec: spec) {
                fullscreenArtifact = nil
            }
        }
        .accessibilityIdentifier("chat-preview")
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        macLayout
        #else
        iosLayout
        #endif
    }

    #if os(macOS)
    private var macLayout: some View {
        HStack(spacing: 0) {
            transcriptSurface
                .frame(minWidth: 520)
            if let spec = activeArtifact {
                Divider().overlay(ThoxTheme.separator)
                ArtifactPanel(
                    spec: spec,
                    onClose: { activeArtifact = nil },
                    onFullscreen: { fullscreenArtifact = spec },
                    activeTab: $artifactTab
                )
                .frame(width: 420)
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: activeArtifact)
    }
    #endif

    #if os(iOS)
    private var iosLayout: some View {
        transcriptSurface
            .sheet(item: $activeArtifact) { spec in
                NavigationStack {
                    ArtifactPanel(
                        spec: spec,
                        onClose: { activeArtifact = nil },
                        onFullscreen: {
                            activeArtifact = nil
                            fullscreenArtifact = spec
                        },
                        activeTab: $artifactTab
                    )
                    .navigationTitle("Artifact")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.large])
            }
    }
    #endif

    private var transcriptSurface: some View {
        VStack(spacing: 0) {
            evidenceBanner
            Divider().overlay(ThoxTheme.separator)
            transcript
            Divider().overlay(ThoxTheme.separator)
            composer
        }
    }

    // MARK: - Evidence banner

    @ViewBuilder
    private var evidenceBanner: some View {
        if model.isEvidenceBannerVisible {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(ThoxTheme.accent)
                    Text("Fixture preview · no live model connected")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(ThoxTheme.primaryText)
                    Spacer(minLength: 0)
                    Text("WR-004")
                        .font(.caption.monospaced().weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(ThoxTheme.accent.opacity(0.18), in: Capsule())
                        .foregroundStyle(ThoxTheme.accent)
                }
                Text(bannerSubtitle)
                    .font(.caption)
                    .foregroundStyle(ThoxTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.missingEvidence, id: \.rawValue) { requirement in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(requirement.presentationTitle)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ThoxTheme.primaryText)
                                Text(requirement.presentationSummary)
                                    .font(.caption)
                                    .foregroundStyle(ThoxTheme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                            .accessibilityIdentifier("chat-preview-evidence-\(requirement.rawValue)")
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text("Evidence pending (\(model.missingEvidence.count))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ThoxTheme.accent)
                }
                .accessibilityIdentifier("chat-preview-evidence-disclosure")
            }
            .padding(12)
            .background(ThoxTheme.surface)
            .accessibilityIdentifier("chat-preview-evidence-banner")
        }
    }

    private var bannerSubtitle: String {
        "Rendering the golden ThoxBlock fixture in \(model.workspaceLabel) (\(model.boundaryLabel)). Live chat stays fail-closed until the authenticated capture below lands."
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(model.turns) { turn in
                        turnView(turn)
                            .id(turn.id)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .frame(maxWidth: 780, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .onChange(of: model.turns.count) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
        }
    }

    private static let bottomAnchor = "chat-preview-bottom"

    @ViewBuilder
    private func turnView(_ turn: ChatTurn) -> some View {
        switch turn.role {
        case .user:
            userTurnView(turn)
        case .assistant:
            assistantTurnView(turn)
        }
    }

    private func userTurnView(_ turn: ChatTurn) -> some View {
        HStack(alignment: .top) {
            Spacer(minLength: 40)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(turn.blocks.enumerated()), id: \.offset) { _, block in
                    ChatBlockView(block: block, onOpenArtifact: openArtifact)
                }
            }
            .padding(12)
            .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(ThoxTheme.separator) }
            .frame(maxWidth: 520, alignment: .trailing)
        }
        .accessibilityIdentifier("chat-turn-user")
    }

    private func assistantTurnView(_ turn: ChatTurn) -> some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(turn.blocks.enumerated()), id: \.offset) { _, block in
                    ChatBlockView(block: block, onOpenArtifact: openArtifact)
                }
            }
            .padding(14)
            .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(ThoxTheme.separator) }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("chat-turn-assistant")
    }

    private var avatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(
                    LinearGradient(
                        colors: [ThoxTheme.accent, Color(red: 0.04, green: 0.49, blue: 0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("TX")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.white)
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                composerField
                submitButton
                if model.turns.contains(where: { $0.role == .user }) {
                    Button {
                        model.restoreGolden()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Reset transcript to golden fixture")
                    .accessibilityIdentifier("chat-preview-reset")
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(ThoxTheme.secondaryText)
                Text(composerHelp)
                    .font(.caption)
                    .foregroundStyle(ThoxTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: 780)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(ThoxTheme.background)
    }

    @ViewBuilder
    private var composerField: some View {
        #if os(iOS)
        TextField("Ask anything…", text: $model.draft, axis: .vertical)
            .lineLimit(1...6)
            .textFieldStyle(.plain)
            .padding(12)
            .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(ThoxTheme.separator) }
            .submitLabel(.send)
            .onSubmit { model.submitDraft() }
            .accessibilityIdentifier("chat-preview-composer")
        #else
        TextField("Ask anything…", text: $model.draft, axis: .vertical)
            .lineLimit(1...6)
            .textFieldStyle(.plain)
            .padding(12)
            .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(ThoxTheme.separator) }
            .onSubmit { model.submitDraft() }
            .accessibilityIdentifier("chat-preview-composer")
        #endif
    }

    private var submitButton: some View {
        Button {
            model.submitDraft()
        } label: {
            Label(model.composerActionLabel, systemImage: "arrow.up")
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(!model.canSubmit)
        .accessibilityIdentifier("chat-preview-send")
    }

    private var composerHelp: String {
        model.contract.isAvailable
            ? "Live chat is on. Prompts leave this device only through the workspace-scoped transport."
            : "Preview only: your prompt is added to the transcript so you can inspect layout. No model is contacted."
    }

    // MARK: - Actions

    private func openArtifact(_ spec: ArtifactSpec) {
        activeArtifact = spec
        artifactTab = .preview
    }
}

// Allow `.sheet(item:)` on both platforms.
extension ArtifactSpec: Identifiable {
    var id: String { artifactID }
}

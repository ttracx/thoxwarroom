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
                    if model.turns.isEmpty && !model.isStreaming {
                        emptyState
                    }
                    ForEach(model.turns) { turn in
                        turnView(turn)
                            .id(turn.id)
                    }
                    if model.isStreaming {
                        streamingTurnView
                            .id(Self.streamingAnchor)
                    }
                    if let error = model.lastError {
                        errorRow(error)
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
            .onChange(of: model.streamingBlocks.count) { _, _ in
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        }
    }

    private static let streamingAnchor = "chat-preview-streaming"

    private var streamingTurnView: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 12) {
                if let reasoning = model.streamingReasoning, !reasoning.isEmpty {
                    reasoningDisclosure(text: reasoning, isOpen: model.streamingReasoningOpen)
                }
                ForEach(Array(model.streamingBlocks.enumerated()), id: \.offset) { _, block in
                    ChatBlockView(block: block, onOpenArtifact: openArtifact)
                }
                streamingCaret
            }
            .padding(14)
            .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(ThoxTheme.accent.opacity(0.35)) }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("chat-turn-streaming")
    }

    private var streamingCaret: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(model.engine.title == "On-device" ? "Thinking on-device…" : "Streaming…")
                .font(.caption)
                .foregroundStyle(ThoxTheme.secondaryText)
        }
        .accessibilityLabel("The assistant is still replying.")
    }

    private func reasoningDisclosure(text: String, isOpen: Bool) -> some View {
        DisclosureGroup {
            Text(text)
                .font(.callout)
                .foregroundStyle(ThoxTheme.secondaryText)
                .textSelection(.enabled)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(isOpen ? "thinking…" : "reasoning")
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(ThoxTheme.secondaryText)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("chat-preview-reasoning")
    }

    private func errorRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
            Text(text)
                .font(.callout)
                .foregroundStyle(ThoxTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.4)) }
        .accessibilityIdentifier("chat-preview-error")
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
                turnActions(turn)
            }
            .padding(14)
            .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14).stroke(ThoxTheme.borderStrong, lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                Rectangle().fill(ThoxTheme.accent.opacity(0.7)).frame(width: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("chat-turn-assistant")
    }

    private var avatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(
                    LinearGradient(
                        colors: [ThoxTheme.accentLight, ThoxTheme.accentDeep],
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

    // MARK: - Empty state

    /// Shown when the transcript is cleared. Mirrors the ThoxMythos empty
    /// state: product name, one honest sentence about what the surface does,
    /// and four starters that prefill the composer rather than sending.
    private var emptyState: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("ThoxOS chat")
                    .font(.title2.monospaced().weight(.bold))
                    .foregroundStyle(ThoxTheme.accent)
                Text(emptyStateSubtitle)
                    .font(.callout)
                    .foregroundStyle(ThoxTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)
            }

            VStack(spacing: 8) {
                ForEach(Self.starters, id: \.self) { starter in
                    Button {
                        model.prefill(starter)
                    } label: {
                        Text(starter)
                            .font(.callout)
                            .foregroundStyle(ThoxTheme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(
                                ThoxTheme.surface,
                                in: RoundedRectangle(cornerRadius: ThoxTheme.controlRadius)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: ThoxTheme.controlRadius)
                                    .stroke(ThoxTheme.borderStrong, lineWidth: 1)
                            }
                            .contentShape(
                                RoundedRectangle(cornerRadius: ThoxTheme.controlRadius)
                            )
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: ThoxTheme.hitTarget)
                    .accessibilityHint("Fills the composer with this prompt")
                }
            }
            .frame(maxWidth: 520)

            Button("Restore the golden fixture") { model.restoreGolden() }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ThoxTheme.accentLight)
                .accessibilityIdentifier("chat-preview-restore-golden")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .accessibilityIdentifier("chat-preview-empty-state")
    }

    private var emptyStateSubtitle: String {
        model.contract.isAvailable
            ? "Connected to \(model.workspaceLabel) (\(model.boundaryLabel))."
            : "\(model.workspaceLabel) · \(model.boundaryLabel). The remote provider stays fail-closed until its contract evidence lands; the on-device and scripted engines run with no egress."
    }

    /// Starters describe what this surface can actually demonstrate today. None
    /// of them promise a remote model.
    private static let starters: [String] = [
        "Show me every block type on the ThoxOS chat surface.",
        "Render a flow diagram of the ThoxRoute path.",
        "Write a TypeScript helper and highlight it.",
        "What evidence is still missing before live chat turns on?"
    ]

    // MARK: - Turn actions

    /// Copy affordance under a finished assistant turn. Always visible rather
    /// than hover-revealed: hover is not a gesture that exists on iOS, and a
    /// control the operator cannot find is a control that does not exist.
    private func turnActions(_ turn: ChatTurn) -> some View {
        HStack(spacing: 12) {
            ChatCopyButton(text: turn.blocks.plainText, label: "Copy response")
                .accessibilityIdentifier("chat-turn-copy")
            Text("\(turn.blocks.count) block\(turn.blocks.count == 1 ? "" : "s")")
                .font(.caption2.monospaced())
                .foregroundStyle(ThoxTheme.faintText)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            enginePickerRow
            HStack(alignment: .bottom, spacing: 8) {
                composerField
                if model.isStreaming {
                    stopButton
                } else {
                    submitButton
                }
                if !model.turns.isEmpty {
                    Button {
                        model.startNewChat()
                    } label: {
                        Label("New chat", systemImage: "square.and.pencil")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isStreaming)
                    .accessibilityLabel("Start a new chat")
                    .accessibilityIdentifier("chat-preview-new-chat")
                }
                if model.turns.contains(where: { $0.role == .user }) {
                    Button {
                        model.restoreGolden()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isStreaming)
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

    private var enginePickerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: engineIcon(for: model.engine))
                .foregroundStyle(ThoxTheme.accent)
            Picker("Engine", selection: $model.engine) {
                ForEach(model.availableEngines) { engine in
                    Text(engine.title).tag(engine)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("chat-preview-engine-picker")
            Text(engineDetail)
                .font(.caption)
                .foregroundStyle(ThoxTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let reason = model.engineUnavailableReason {
                Label(reason, systemImage: "info.circle")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(ThoxTheme.secondaryText)
                    .help(reason)
                    .accessibilityLabel(reason)
                    .accessibilityIdentifier("chat-preview-engine-unavailable")
            }
        }
    }

    private func engineIcon(for engine: WarRoomChatEngine) -> String { engine.symbol }

    private var engineDetail: String { model.engine.detail }

    private var stopButton: some View {
        Button(role: .destructive) {
            model.cancelStream()
        } label: {
            Label("Stop", systemImage: "stop.fill")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("chat-preview-stop")
        .accessibilityLabel("Stop generating")
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
        if model.activeTransport.isReady {
            switch model.engine {
            case .appleIntelligence:
                return "On-device engine: prompts never leave this Mac / iPad. Streams token-by-token."
            case .scripted:
                return "Fixture engine: replays the golden ThoxBlock stream with pacing so you can review layout and screenshots."
            case .provider:
                return "Live chat is on. Prompts leave this device only through the workspace-scoped transport."
            }
        }
        return model.engineUnavailableReason
            ?? "Preview only: your prompt is added to the transcript so you can inspect layout. No model is contacted."
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

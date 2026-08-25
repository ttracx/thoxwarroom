// WarRoomChatPreviewModel.swift
// State model for the block-based chat *presentation* surface. This does not
// talk to a provider — the live transport is fail-closed behind
// `OpenWebUIProvider.nativeChatContract` (WR-004) until authenticated evidence
// is captured. The preview loads the golden fixture, exposes the contract
// gate to the view so the surface can render an honest "why chat is disabled"
// banner, and lets the user append a new user turn to inspect layout without
// inventing a response DTO.

import Foundation
import SwiftUI
import WarRoomCore
import WarRoomOpenWebUI

@MainActor
final class WarRoomChatPreviewModel: ObservableObject {
    /// Turns shown in the transcript. Seeded with the golden fixture so the
    /// surface has non-empty content on first view.
    @Published private(set) var turns: [ChatTurn]

    /// Composer draft text.
    @Published var draft: String = ""

    /// Live assistant text as it streams in. Nil when no turn is in flight.
    /// Parsed on every delta by `WarRoomChatStreamParser` and rendered as
    /// preview blocks alongside a caret-blinking indicator.
    @Published private(set) var streamingRaw: String?

    /// Blocks derived from `streamingRaw`. Recomputed after each delta so a
    /// half-arrived code fence appears as `.pendingCode` rather than being
    /// re-classified as prose on the next character.
    @Published private(set) var streamingBlocks: [ThoxBlock] = []

    /// Reasoning captured during streaming, if the model emits `<think>`.
    @Published private(set) var streamingReasoning: String?
    @Published private(set) var streamingReasoningOpen: Bool = false

    /// Currently active engine.
    @Published var engine: WarRoomChatEngine

    /// Non-terminal transport error, sanitized for display.
    @Published private(set) var lastError: String?

    /// The evidence gate for native chat. The view uses this to render an
    /// honest disabled-composer state.
    let contract: OpenWebUINativeChatContract

    /// Non-sensitive workspace label used in headers/badges.
    let workspaceLabel: String

    /// Boundary printed under the workspace label.
    let boundaryLabel: String

    /// Engines this device can actually offer.
    let availableEngines: [WarRoomChatEngine]

    private var streamingTask: Task<Void, Never>?
    private var transportFactory: (WarRoomChatEngine) -> any ChatTransport

    init(
        workspaceLabel: String,
        boundaryLabel: String,
        contract: OpenWebUINativeChatContract = OpenWebUIProvider.nativeChatContract,
        seed: [ChatTurn] = ChatFixture.goldenTranscript,
        engine: WarRoomChatEngine? = nil,
        availableEngines: [WarRoomChatEngine]? = nil,
        transportFactory: ((WarRoomChatEngine) -> any ChatTransport)? = nil
    ) {
        self.workspaceLabel = workspaceLabel
        self.boundaryLabel = boundaryLabel
        self.contract = contract
        self.turns = seed
        let engines = availableEngines ?? WarRoomChatEngineResolver.availableEngines()
        self.availableEngines = engines
        self.engine = engine ?? WarRoomChatEngineResolver.defaultEngine()
        let missing = contract.missingEvidence.count
        self.transportFactory = transportFactory ?? { engine in
            WarRoomChatEngineResolver.transport(for: engine, missingEvidenceCount: missing)
        }
    }

    /// The composer button title. "Send" is only advertised when the active
    /// engine can actually run a turn — the provider engine stays disabled
    /// while the WR-004 evidence gate is closed.
    var composerActionLabel: String {
        activeTransport.isReady ? "Send" : "Preview"
    }

    /// True when the composer accepts a submission.
    var canSubmit: Bool {
        guard !isStreaming else { return false }
        return !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True when the surface should render the evidence banner. Independent of
    /// engine selection — the banner exists to explain why the *remote*
    /// provider is off, so it shows whenever the evidence gate is closed.
    var isEvidenceBannerVisible: Bool { !contract.isAvailable }

    /// True while a turn is streaming.
    var isStreaming: Bool { streamingRaw != nil }

    /// Sorted list of missing evidence, deterministic for tests.
    var missingEvidence: [OpenWebUINativeChatEvidenceRequirement] {
        contract.missingEvidence.sorted { $0.presentationOrder < $1.presentationOrder }
    }

    /// Transport for the currently selected engine.
    var activeTransport: any ChatTransport { transportFactory(engine) }

    /// One-line explanation shown when the active engine cannot stream.
    var engineUnavailableReason: String? {
        let transport = activeTransport
        return transport.isReady ? nil : transport.unavailableReason
    }

    /// Append a user turn to the transcript and (when the active transport is
    /// ready) start streaming an assistant reply. When the transport is not
    /// ready the user turn is still captured so the transcript stays truthful
    /// and the banner explains what happened.
    func submitDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft = ""
        lastError = nil
        turns.append(ChatTurn(role: .user, blocks: [.markdown(trimmed)]))

        let transport = activeTransport
        guard transport.isReady else { return }

        streamingRaw = ""
        streamingBlocks = []
        streamingReasoning = nil
        streamingReasoningOpen = false

        let history = turns.map { turn -> ChatExchange in
            let role: ChatExchange.Role = (turn.role == .user) ? .user : .assistant
            return ChatExchange(role: role, text: turn.blocks.plainText)
        }

        streamingTask = Task { [weak self] in
            guard let self else { return }
            let stream = transport.stream(history: history, options: .default)
            var accumulated = ""
            for await event in stream {
                if Task.isCancelled { break }
                switch event {
                case .delta(let chunk):
                    accumulated.append(chunk)
                    await self.apply(streamedText: accumulated)
                case .completed:
                    await self.completeStream(finalText: accumulated)
                    return
                case .failed(let reason):
                    await self.failStream(reason: reason)
                    return
                }
            }
            await self.completeStream(finalText: accumulated)
        }
    }

    /// Cancel an in-flight stream. Any partial content already received is
    /// promoted to a finished turn so the transcript never loses text the user
    /// already saw.
    func cancelStream() {
        guard isStreaming else { return }
        streamingTask?.cancel()
        streamingTask = nil
        let partial = streamingRaw ?? ""
        let parsed = WarRoomChatStreamParser.parse(partial)
        appendAssistantIfNonEmpty(parsed)
        streamingRaw = nil
        streamingBlocks = []
        streamingReasoning = nil
        streamingReasoningOpen = false
    }

    /// Clear the transcript to the empty state.
    ///
    /// The empty state is not decoration: it is where the surface states what
    /// this workspace is, which engine is selected, and what it will and will
    /// not do. Seeding every session with the golden fixture hides that.
    func startNewChat() {
        cancelStream()
        turns = []
        draft = ""
        lastError = nil
    }

    /// Prefill the composer from a suggestion chip without sending, so the
    /// operator can edit it first. Ignored mid-stream.
    func prefill(_ text: String) {
        guard !isStreaming else { return }
        draft = text
    }

    /// Reset back to the golden fixture. Used by the "Restore golden preview"
    /// affordance to make screenshot recovery cheap.
    func restoreGolden() {
        cancelStream()
        turns = ChatFixture.goldenTranscript
        draft = ""
        lastError = nil
    }

    // MARK: - Stream lifecycle

    private func apply(streamedText: String) {
        let parsed = WarRoomChatStreamParser.parse(streamedText)
        streamingRaw = streamedText
        streamingBlocks = parsed.blocks
        streamingReasoning = parsed.reasoning
        streamingReasoningOpen = parsed.isReasoningOpen
    }

    private func completeStream(finalText: String) {
        streamingTask = nil
        let parsed = WarRoomChatStreamParser.parse(finalText)
        appendAssistantIfNonEmpty(parsed)
        streamingRaw = nil
        streamingBlocks = []
        streamingReasoning = nil
        streamingReasoningOpen = false
    }

    private func failStream(reason: String) {
        streamingTask = nil
        let parsed = WarRoomChatStreamParser.parse(streamingRaw ?? "")
        appendAssistantIfNonEmpty(parsed)
        streamingRaw = nil
        streamingBlocks = []
        streamingReasoning = nil
        streamingReasoningOpen = false
        lastError = reason
    }

    private func appendAssistantIfNonEmpty(_ parsed: ParsedAssistantMessage) {
        var blocks: [ThoxBlock] = []
        if let reasoning = parsed.reasoning, !reasoning.isEmpty {
            blocks.append(.markdown("_reasoning_\n\n\(reasoning)"))
        }
        blocks.append(contentsOf: parsed.blocks)
        guard !blocks.isEmpty else { return }
        turns.append(ChatTurn(role: .assistant, blocks: blocks))
    }
}

extension Array where Element == ThoxBlock {
    /// Plain-text projection used when a turn is passed to a transport.
    /// Rich blocks collapse to their most literal representation so the model
    /// sees what the user saw, without smuggling render decisions in.
    var plainText: String {
        map { block -> String in
            switch block {
            case .markdown(let text): return text
            case .code(let language, let source): return "```\(language)\n\(source)\n```"
            case .pendingCode(let language, let partial): return "```\(language)\n\(partial)"
            case .chart(let spec): return "[chart: \(spec.title)]"
            case .mermaid(let source): return "```mermaid\n\(source)\n```"
            case .artifact(let spec): return "[artifact: \(spec.title)]"
            case .sandpack(let spec): return "[sandpack: \(spec.template)]"
            case .digitalHuman(let spec): return "[digital human: \(spec.persona)] \(spec.text)"
            }
        }
        .joined(separator: "\n\n")
    }
}

extension OpenWebUINativeChatEvidenceRequirement {
    /// Ordered label suitable for a list row.
    var presentationTitle: String {
        switch self {
        case .credentialLifecycle: return "Credential lifecycle"
        case .nonStreamingRequest: return "Non-streaming request DTO"
        case .nonStreamingResponse: return "Non-streaming response DTO"
        case .streamingTransport: return "Streaming transport headers"
        case .streamingFrames: return "Streaming frame schema"
        case .cancellation: return "Cancellation semantics"
        case .errorResponses: return "Error response envelopes"
        case .durableHistory: return "Durable conversation history"
        case .sourceCitations: return "Source citation shape"
        }
    }

    /// One-line explanation, matched to `docs/current_service_contracts.md`.
    var presentationSummary: String {
        switch self {
        case .credentialLifecycle: return "How bearer tokens are issued, refreshed, revoked, and logged out."
        case .nonStreamingRequest: return "Authenticated request field names, types, and bounds."
        case .nonStreamingResponse: return "Authenticated success response envelope."
        case .streamingTransport: return "SSE / chunked transport, content type, and headers."
        case .streamingFrames: return "Frame schema, ordering, and normal termination marker."
        case .cancellation: return "Server behavior and client semantics when the user stops a run."
        case .errorResponses: return "Sanitized authentication, validation, and server error shapes."
        case .durableHistory: return "Minimum create/update/list/get sequence for stored conversations."
        case .sourceCitations: return "Citation and source field shapes, including their absence."
        }
    }

    /// Deterministic order for test comparisons.
    fileprivate var presentationOrder: Int {
        switch self {
        case .credentialLifecycle: return 0
        case .nonStreamingRequest: return 1
        case .nonStreamingResponse: return 2
        case .streamingTransport: return 3
        case .streamingFrames: return 4
        case .cancellation: return 5
        case .errorResponses: return 6
        case .durableHistory: return 7
        case .sourceCitations: return 8
        }
    }
}

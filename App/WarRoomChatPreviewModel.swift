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

    /// The evidence gate for native chat. The view uses this to render an
    /// honest disabled-composer state.
    let contract: OpenWebUINativeChatContract

    /// Non-sensitive workspace label used in headers/badges.
    let workspaceLabel: String

    /// Boundary printed under the workspace label.
    let boundaryLabel: String

    init(
        workspaceLabel: String,
        boundaryLabel: String,
        contract: OpenWebUINativeChatContract = OpenWebUIProvider.nativeChatContract,
        seed: [ChatTurn] = ChatFixture.goldenTranscript
    ) {
        self.workspaceLabel = workspaceLabel
        self.boundaryLabel = boundaryLabel
        self.contract = contract
        self.turns = seed
    }

    /// The composer button title. Send is intentionally never advertised as
    /// available while `contract.isAvailable` is `false` — showing "Send" and
    /// then silently dropping the request would look like a live surface that
    /// has stopped responding.
    var composerActionLabel: String { contract.isAvailable ? "Send" : "Preview" }

    /// True when the composer accepts a submission.
    var canSubmit: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True when the surface should render the evidence banner. This is the
    /// hard signal to the user that no model is connected.
    var isEvidenceBannerVisible: Bool { !contract.isAvailable }

    /// Sorted list of missing evidence, deterministic for tests.
    var missingEvidence: [OpenWebUINativeChatEvidenceRequirement] {
        contract.missingEvidence.sorted { $0.presentationOrder < $1.presentationOrder }
    }

    /// Append a user turn to the transcript. In preview mode we deliberately
    /// do not synthesize a fake assistant reply — that would misrepresent the
    /// gated state. The user can see that their prompt is captured while the
    /// banner explains why no reply follows.
    func submitDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        turns.append(ChatTurn(role: .user, blocks: [.markdown(trimmed)]))
        draft = ""
    }

    /// Reset back to the golden fixture. Used by the "Restore golden preview"
    /// affordance to make screenshot recovery cheap.
    func restoreGolden() {
        turns = ChatFixture.goldenTranscript
        draft = ""
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

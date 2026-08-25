// WarRoomChatTransport.swift
// The seam between the chat presentation surface and whatever actually
// produces tokens.
//
// ## Why this exists
//
// WR-004 keeps the Open WebUI native chat contract fail-closed: no authenticated
// capture session has happened, so nine evidence categories are still missing
// and `OpenWebUIProvider.nativeChatContract.isAvailable` is a hard-coded
// `false`. That gate is correct and this file does not weaken it — the provider
// transport below *refuses at construction* and reports exactly which evidence
// is outstanding.
//
// But "we cannot yet prove the remote contract" is not the same as "the user
// cannot chat". Two engines need no remote contract evidence at all:
//
// - `.appleIntelligence` runs Apple's on-device Foundation Models. Nothing
//   leaves the device, so there is no wire contract to capture, no credential
//   lifecycle to prove, and no egress boundary to defend. It is the only engine
//   here that both streams real model output and is available today.
// - `.scripted` replays the checked-in golden fixture. It contacts nothing, and
//   exists so previews, screenshots, and UI tests are deterministic.
//
// Engine selection is therefore an availability question, not a policy
// loophole: `WarRoomChatEngine.availableEngines()` reports what this device can
// actually do, and the provider engine stays unavailable until the evidence
// lands.

import Foundation

// MARK: - Events

/// One event from a running chat turn. Deliberately mirrors the event names on
/// the ThoxMythos reference surface (`delta`, `done`, `error`) so a future
/// remote transport can adopt this seam without renaming.
enum ChatStreamEvent: Equatable {
    /// Incremental text. Deltas are *incremental*, never cumulative — every
    /// transport is responsible for converting its own wire shape to deltas.
    case delta(String)

    /// Terminal success.
    case completed

    /// Terminal failure carrying a message already safe to display.
    case failed(String)
}

// MARK: - Transport

/// Produces an assistant turn for a bounded message history.
///
/// Conformances must be `Sendable` because a turn is driven from a detached
/// task and cancelled by dropping that task.
protocol ChatTransport: Sendable {
    /// Human-readable engine name shown in the header pill.
    var engineLabel: String { get }

    /// True when a turn can actually be started right now.
    var isReady: Bool { get }

    /// Non-nil when the transport cannot run, explaining why in one sentence.
    var unavailableReason: String? { get }

    /// Stream one assistant turn.
    ///
    /// Implementations must honour `Task.isCancelled` promptly and must finish
    /// the stream (rather than hanging) when cancelled.
    func stream(history: [ChatExchange], options: ChatGenerationOptions) -> AsyncStream<ChatStreamEvent>
}

/// One prior turn, flattened to plain text for the model.
struct ChatExchange: Equatable, Sendable {
    enum Role: String, Equatable, Sendable {
        case user
        case assistant
    }

    let role: Role
    let text: String
}

/// Bounded generation parameters. Values match the ThoxMythos reference
/// surface so behaviour is comparable across the two clients.
struct ChatGenerationOptions: Equatable, Sendable {
    var temperature: Double = 0.7
    var maxTokens: Int = 1024
    var systemInstruction: String?

    static let `default` = ChatGenerationOptions()
}

// MARK: - Engine selection

/// Which engine backs the chat surface.
enum WarRoomChatEngine: String, CaseIterable, Identifiable, Sendable {
    /// Apple on-device Foundation Models. Private by construction.
    case appleIntelligence

    /// Deterministic replay of the checked-in golden fixture.
    case scripted

    /// Remote Open WebUI native chat — fail-closed pending WR-004 evidence.
    case provider

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleIntelligence: return "On-device"
        case .scripted: return "Golden fixture"
        case .provider: return "Workspace provider"
        }
    }

    var detail: String {
        switch self {
        case .appleIntelligence:
            return "Apple Foundation Models running on this device. Prompts never leave the machine."
        case .scripted:
            return "Replays the checked-in golden transcript. Contacts nothing; used for review and tests."
        case .provider:
            return "Streams from the workspace endpoint. Disabled until the authenticated capture qualifies."
        }
    }

    var symbol: String {
        switch self {
        case .appleIntelligence: return "cpu"
        case .scripted: return "text.book.closed"
        case .provider: return "network"
        }
    }
}

// MARK: - Fail-closed provider transport

/// The remote engine. Always refuses, and says precisely why.
///
/// This intentionally has no code path that could ever emit a token: rather
/// than checking a flag at send time, it reports `isReady == false` and returns
/// a single `.failed` event. There is no branch to accidentally enable.
struct FailClosedProviderChatTransport: ChatTransport {
    let missingEvidenceCount: Int

    init(missingEvidenceCount: Int) {
        self.missingEvidenceCount = missingEvidenceCount
    }

    var engineLabel: String { "Workspace provider" }

    var isReady: Bool { false }

    var unavailableReason: String? {
        "Native chat stays fail-closed until \(missingEvidenceCount) authenticated evidence categories are captured and reviewed (WR-004)."
    }

    func stream(history: [ChatExchange], options: ChatGenerationOptions) -> AsyncStream<ChatStreamEvent> {
        let reason = unavailableReason ?? "Unavailable."
        return AsyncStream { continuation in
            continuation.yield(.failed(reason))
            continuation.finish()
        }
    }
}

// MARK: - Scripted transport

/// Replays a fixed script with realistic pacing so the streaming surface can be
/// reviewed, screenshotted, and UI-tested without a model.
struct ScriptedChatTransport: ChatTransport {
    /// Milliseconds between emitted chunks. `0` emits everything immediately,
    /// which is what tests want.
    let chunkDelayMilliseconds: UInt64

    /// The script to replay.
    let script: String

    init(script: String = ScriptedChatTransport.goldenScript, chunkDelayMilliseconds: UInt64 = 18) {
        self.script = script
        self.chunkDelayMilliseconds = chunkDelayMilliseconds
    }

    var engineLabel: String { "Golden fixture" }
    var isReady: Bool { true }
    var unavailableReason: String? { nil }

    func stream(history: [ChatExchange], options: ChatGenerationOptions) -> AsyncStream<ChatStreamEvent> {
        // Chunk on word boundaries rather than characters: it is ~8x fewer
        // re-parses per turn and reads more like real token streaming.
        let chunks = Self.chunk(script)
        let delay = chunkDelayMilliseconds

        return AsyncStream { continuation in
            let task = Task {
                for chunk in chunks {
                    if Task.isCancelled { break }
                    continuation.yield(.delta(chunk))
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: delay * 1_000_000)
                    }
                }
                continuation.yield(.completed)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Split into word-sized chunks, preserving all whitespace exactly so code
    /// fences and indentation survive the round trip.
    static func chunk(_ text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == " " || character == "\n" {
                chunks.append(current)
                current = ""
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// The golden script. Exercises every block type the renderer supports,
    /// including a reasoning section, so one run reviews the whole surface.
    static let goldenScript: String = """
    <think>
    The user wants to see the full block surface. I will emit one of each type \
    so the renderer can be reviewed end to end.
    </think>
    **ThoxOS chat** renders a typed block stream. This paragraph is Markdown with a list and an inline `code` span:

    - sanitized, bounded rendering
    - language-tagged code
    - typed directive blocks

    ```typescript
    // F1 — highlighted, copyable
    async function ask(q: string) {
      const r = await ox.chat([{ role: 'user', content: q }], { reasoning: true });
      return r.content;
    }
    ```

    ```thoxchart
    {"kind":"line","title":"Fleet tokens / hr","labels":["Mon","Tue","Wed","Thu","Fri"],"values":[12,19,15,27,32]}
    ```

    ```mermaid
    graph LR; U[User]-->C[ThoxOS Chat]; C-->R[ThoxRoute]; R-->O[ox-alpha]; R-->L[Local model]
    ```

    ```thoxagent
    {"persona":"Victoria","status":"awaiting_approval","text":"Drafting the launch reply and classifying 3 inbox threads. Crossing an external boundary (send) will pause for your approval."}
    ```

    That is every block type on the surface.
    """
}

// MARK: - Apple on-device transport

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Streams from Apple's on-device Foundation Models.
///
/// This is the engine that makes the surface genuinely usable today. It needs
/// no remote-contract evidence because it performs no egress: the model runs in
/// the system process on this device, so there is no credential lifecycle, no
/// wire schema, and no boundary to defend.
///
/// Availability is layered and each layer degrades to a specific, actionable
/// message rather than a generic failure:
/// - built without the framework (older SDK) → not offered;
/// - running on an OS older than the framework requires → not offered;
/// - hardware unsupported / Apple Intelligence off / model still downloading →
///   offered but not ready, with the system's own reason surfaced.
struct AppleIntelligenceChatTransport: ChatTransport {

    /// Whether this device can host the engine at all. Checked before the
    /// engine is offered in the picker.
    static var isSupported: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
        #else
        return false
        #endif
    }

    /// The system's reason for being unavailable, mapped to a sentence the user
    /// can act on.
    static var systemUnavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return "This device does not support Apple Intelligence."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in System Settings to use the on-device engine."
            case .unavailable(.modelNotReady):
                return "The on-device model is still downloading. This finishes in the background."
            case .unavailable:
                return "The on-device model is unavailable on this device."
            }
        }
        return "The on-device engine requires macOS 26 or iOS 26."
        #else
        return "This build was compiled without the on-device model framework."
        #endif
    }

    var engineLabel: String { "On-device" }

    var isReady: Bool { Self.isSupported }

    var unavailableReason: String? { Self.systemUnavailableReason }

    func stream(history: [ChatExchange], options: ChatGenerationOptions) -> AsyncStream<ChatStreamEvent> {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            return Self.streamFoundationModels(history: history, options: options)
        }
        #endif
        let reason = Self.systemUnavailableReason ?? "The on-device engine is unavailable."
        return AsyncStream { continuation in
            continuation.yield(.failed(reason))
            continuation.finish()
        }
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, *)
    private static func streamFoundationModels(
        history: [ChatExchange],
        options: ChatGenerationOptions
    ) -> AsyncStream<ChatStreamEvent> {
        let instructions = options.systemInstruction ?? defaultInstructions
        let prompt = flatten(history)

        return AsyncStream { continuation in
            let task = Task {
                do {
                    let session = LanguageModelSession(instructions: instructions)
                    let generation = GenerationOptions(temperature: options.temperature)

                    // The framework yields *cumulative* snapshots. The surface
                    // contract is incremental deltas, so diff against what we
                    // have already emitted. Snapshots are monotonic, but guard
                    // the prefix anyway: if a snapshot ever fails to extend the
                    // previous one, emitting the whole snapshot is still
                    // correct output, just a redundant repaint.
                    var emitted = ""
                    let responses = session.streamResponse(to: prompt, options: generation)

                    for try await snapshot in responses {
                        if Task.isCancelled { break }
                        let text = snapshot.content
                        guard text.count > emitted.count, text.hasPrefix(emitted) else {
                            if text != emitted {
                                emitted = text
                                continuation.yield(.delta(text))
                            }
                            continue
                        }
                        let delta = String(text.dropFirst(emitted.count))
                        emitted = text
                        continuation.yield(.delta(delta))
                    }

                    continuation.yield(.completed)
                } catch is CancellationError {
                    continuation.yield(.completed)
                } catch {
                    continuation.yield(.failed(Self.describe(error)))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Map framework errors to messages that say what the user can do, and
    /// never echo raw prompt content back into the UI.
    @available(macOS 26.0, iOS 26.0, *)
    private static func describe(_ error: Error) -> String {
        if let generation = error as? LanguageModelSession.GenerationError {
            switch generation {
            case .exceededContextWindowSize:
                return "This conversation is too long for the on-device model. Start a new chat to continue."
            case .guardrailViolation:
                return "The on-device model declined this request."
            case .unsupportedLanguageOrLocale:
                return "The on-device model does not support this language."
            case .assetsUnavailable:
                return "The on-device model assets are not available yet."
            default:
                return "The on-device model could not complete this turn."
            }
        }
        return "The on-device model could not complete this turn."
    }
    #endif

    /// Default persona. Kept short: long instructions consume the on-device
    /// context window that the conversation itself needs.
    static let defaultInstructions = """
    You are ThoxOS, a concise technical assistant running privately on this device. \
    Prefer short, direct answers. Use fenced code blocks with a language tag for code.
    """

    /// Flatten the bounded history into a single prompt.
    ///
    /// The last user turn is the actual request; earlier turns are supplied as
    /// labelled context. This keeps one prompt shape across framework versions
    /// rather than depending on a transcript API that has moved between betas.
    static func flatten(_ history: [ChatExchange]) -> String {
        guard let last = history.last, last.role == .user else {
            return history.last?.text ?? ""
        }
        let priorTurns = history.dropLast()
        guard !priorTurns.isEmpty else { return last.text }

        let context = priorTurns
            .map { "\($0.role == .user ? "User" : "Assistant"): \($0.text)" }
            .joined(separator: "\n")

        return """
        Earlier in this conversation:
        \(context)

        User: \(last.text)
        """
    }
}

// MARK: - Engine resolution

/// Builds transports and reports which engines this device can offer.
enum WarRoomChatEngineResolver {

    /// Engines offered in the picker, best-first.
    ///
    /// The provider engine is always listed — hiding it would make the WR-004
    /// gate invisible, and the user is better served by seeing the engine and
    /// the reason it is off than by seeing nothing.
    static func availableEngines() -> [WarRoomChatEngine] {
        var engines: [WarRoomChatEngine] = []
        if AppleIntelligenceChatTransport.isSupported {
            engines.append(.appleIntelligence)
        }
        engines.append(.scripted)
        engines.append(.provider)
        return engines
    }

    /// The engine to start on: a real on-device model when one exists, else the
    /// fixture, which is honest about being a fixture.
    static func defaultEngine() -> WarRoomChatEngine {
        AppleIntelligenceChatTransport.isSupported ? .appleIntelligence : .scripted
    }

    /// Build the transport for an engine.
    static func transport(
        for engine: WarRoomChatEngine,
        missingEvidenceCount: Int
    ) -> any ChatTransport {
        switch engine {
        case .appleIntelligence:
            return AppleIntelligenceChatTransport()
        case .scripted:
            return ScriptedChatTransport()
        case .provider:
            return FailClosedProviderChatTransport(missingEvidenceCount: missingEvidenceCount)
        }
    }
}

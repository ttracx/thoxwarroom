import XCTest
import WarRoomCore
import WarRoomOpenWebUI
@testable import ThoxWarRoom

@MainActor
final class WarRoomChatPreviewTests: XCTestCase {

    // MARK: - Helpers

    private func makeModel(
        engine: WarRoomChatEngine = .scripted,
        transport: (any ChatTransport)? = nil,
        contract: OpenWebUINativeChatContract = OpenWebUIProvider.nativeChatContract,
        seed: [ChatTurn] = ChatFixture.goldenTranscript
    ) -> WarRoomChatPreviewModel {
        let resolved: any ChatTransport = transport
            ?? WarRoomChatEngineResolver.transport(for: engine, missingEvidenceCount: contract.missingEvidence.count)
        return WarRoomChatPreviewModel(
            workspaceLabel: "Research",
            boundaryLabel: "Private network",
            contract: contract,
            seed: seed,
            engine: engine,
            availableEngines: [engine],
            transportFactory: { _ in resolved }
        )
    }

    // MARK: - Fixture parity

    func testGoldenFixtureCoversEveryBlockKind() {
        let kinds = Set(ChatFixture.goldenAssistantBlocks.map(\.kindIdentifier))

        XCTAssertEqual(
            kinds,
            Set(["markdown", "code", "chart", "mermaid", "artifact", "sandpack", "digitalHuman"]),
            "The golden fixture must exercise every ThoxBlock case so the preview surface always covers F1–F6."
        )
    }

    func testGoldenFixtureContainsUserTurnAndAssistantTurn() {
        let transcript = ChatFixture.goldenTranscript

        XCTAssertEqual(transcript.count, 2)
        XCTAssertEqual(transcript.first?.role, .user)
        XCTAssertEqual(transcript.last?.role, .assistant)
        XCTAssertEqual(transcript.last?.blocks.count, ChatFixture.goldenAssistantBlocks.count)
    }

    func testGoldenArtifactHTMLIsBundledInline() {
        guard case let .artifact(spec)? = ChatFixture.goldenAssistantBlocks.first(where: {
            if case .artifact = $0 { return true } else { return false }
        }) else {
            return XCTFail("Golden fixture is missing an artifact block.")
        }

        XCTAssertEqual(spec.artifactID, "a1")
        XCTAssertEqual(spec.kind, "html")
        XCTAssertTrue(spec.source.contains("Increment"), "Bundled artifact HTML should include the increment button.")
        // No external network references — the artifact must be renderable offline.
        XCTAssertFalse(spec.source.lowercased().contains("http://"))
        XCTAssertFalse(spec.source.lowercased().contains("https://"))
    }

    // MARK: - Evidence-gated composer

    func testFreshModelExposesFailClosedContract() {
        let model = makeModel(engine: .provider)

        XCTAssertFalse(model.contract.isAvailable)
        XCTAssertEqual(model.contract.blocker, .authenticatedCaptureRequired)
        XCTAssertTrue(model.isEvidenceBannerVisible)
        XCTAssertEqual(model.composerActionLabel, "Preview")
    }

    func testMissingEvidenceListMatchesProviderContract() {
        let model = makeModel()

        let requirementSet = Set(model.missingEvidence)

        XCTAssertEqual(requirementSet, OpenWebUIProvider.nativeChatContract.missingEvidence)
        // The presentation list is deterministic — future test failures should
        // be a signal that the ordering shifted, not that the set changed.
        XCTAssertEqual(model.missingEvidence.first, .credentialLifecycle)
        XCTAssertEqual(model.missingEvidence.last, .sourceCitations)
    }

    // MARK: - Composer semantics

    func testEmptyOrWhitespaceDraftDoesNotAppendTurn() {
        let model = makeModel(transport: StubTransport())
        let baseline = model.turns.count

        model.draft = "   \n\t"
        model.submitDraft()

        XCTAssertEqual(model.turns.count, baseline)
        XCTAssertFalse(model.canSubmit)
    }

    func testSubmitDraftAppendsUserTurnAndClearsComposer() {
        let model = makeModel(transport: StubTransport(), seed: [])

        model.draft = "Hello ThoxOS"
        XCTAssertTrue(model.canSubmit)

        model.submitDraft()

        XCTAssertEqual(model.turns.first?.role, .user)
        if case let .markdown(text) = model.turns.first?.blocks.first {
            XCTAssertEqual(text, "Hello ThoxOS")
        } else {
            XCTFail("User turn should be a single markdown block.")
        }
        XCTAssertTrue(model.draft.isEmpty)
    }

    func testRestoreGoldenReplacesTranscriptWithFixture() {
        let model = makeModel(transport: StubTransport())
        model.draft = "extra prompt"
        model.submitDraft()

        model.restoreGolden()

        XCTAssertEqual(model.turns.count, ChatFixture.goldenTranscript.count)
        XCTAssertTrue(model.draft.isEmpty)
        XCTAssertNil(model.streamingRaw)
        XCTAssertEqual(model.turns.first?.role, .user)
        XCTAssertEqual(model.turns.last?.role, .assistant)
    }

    // MARK: - Streaming lifecycle

    func testFailClosedProviderTransportRefusesToStreamAndReportsWhy() async {
        let transport = FailClosedProviderChatTransport(missingEvidenceCount: 9)
        XCTAssertFalse(transport.isReady)
        XCTAssertNotNil(transport.unavailableReason)

        var events: [ChatStreamEvent] = []
        for await event in transport.stream(history: [], options: .default) {
            events.append(event)
        }
        XCTAssertEqual(events.count, 1)
        guard case let .failed(reason)? = events.first else {
            return XCTFail("Fail-closed transport must emit exactly one .failed event.")
        }
        XCTAssertTrue(reason.contains("9"))
        XCTAssertTrue(reason.contains("WR-004"))
    }

    func testScriptedTransportEmitsDeltasThatConcatenateToScript() async {
        let script = "Hello, ThoxOS!"
        let transport = ScriptedChatTransport(script: script, chunkDelayMilliseconds: 0)
        var accumulated = ""
        var didComplete = false

        for await event in transport.stream(history: [], options: .default) {
            switch event {
            case .delta(let chunk): accumulated.append(chunk)
            case .completed: didComplete = true
            case .failed(let reason): XCTFail("Unexpected failure: \(reason)")
            }
        }

        XCTAssertTrue(didComplete)
        XCTAssertEqual(accumulated, script)
    }

    func testStreamingCompletesIntoAssistantTurnWithParsedBlocks() async {
        let script = """
        Hello.

        ```swift
        print(\"hi\")
        ```
        """
        let transport = ScriptedChatTransport(script: script, chunkDelayMilliseconds: 0)
        let model = makeModel(engine: .scripted, transport: transport, seed: [])
        model.draft = "please stream a code block"

        model.submitDraft()

        // Wait for the async stream to complete (bounded).
        let deadline = Date().addingTimeInterval(5)
        while model.isStreaming && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertFalse(model.isStreaming)
        XCTAssertEqual(model.turns.count, 2)
        XCTAssertEqual(model.turns.first?.role, .user)
        guard let last = model.turns.last, last.role == .assistant else {
            return XCTFail("Assistant turn missing after stream completion.")
        }
        // The parser must have finished the code fence into a proper `.code`
        // block, not `.pendingCode`.
        XCTAssertTrue(last.blocks.contains { block in
            if case .code = block { return true } else { return false }
        })
    }

    func testCancelStreamPreservesPartialOutputAsFinishedTurn() async {
        // Long enough script that we can cancel mid-stream.
        let script = String(repeating: "streaming word ", count: 200)
        let transport = ScriptedChatTransport(script: script, chunkDelayMilliseconds: 8)
        let model = makeModel(engine: .scripted, transport: transport, seed: [])
        model.draft = "run"
        model.submitDraft()

        // Let a few deltas arrive.
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(model.isStreaming)

        model.cancelStream()

        XCTAssertFalse(model.isStreaming)
        XCTAssertEqual(model.turns.first?.role, .user)
        // Whatever partial content the stream emitted must survive the cancel.
        XCTAssertEqual(model.turns.count, 2)
        XCTAssertEqual(model.turns.last?.role, .assistant)
    }

    // MARK: - Evidence requirement presentation

    func testEvidenceRequirementLabelsAreNonEmpty() {
        for requirement in OpenWebUINativeChatEvidenceRequirement.allCases {
            XCTAssertFalse(
                requirement.presentationTitle.isEmpty,
                "\(requirement.rawValue) is missing a presentation title."
            )
            XCTAssertFalse(
                requirement.presentationSummary.isEmpty,
                "\(requirement.rawValue) is missing a presentation summary."
            )
        }
    }
}

// MARK: - Parser tests

final class WarRoomChatStreamParserTests: XCTestCase {

    func testUnterminatedCodeFenceStaysPendingRatherThanReclassifying() {
        let partial = """
        Here is code:

        ```swift
        print("hello
        """
        let parsed = WarRoomChatStreamParser.parse(partial)

        XCTAssertNil(parsed.reasoning)
        XCTAssertFalse(parsed.isReasoningOpen)
        guard parsed.blocks.count == 2 else {
            return XCTFail("Expected prose + pending fence, got: \(parsed.blocks)")
        }
        if case .markdown = parsed.blocks[0] {} else { XCTFail("First block should be markdown prose.") }
        if case .pendingCode(let language, let partialSource) = parsed.blocks[1] {
            XCTAssertEqual(language, "swift")
            XCTAssertTrue(partialSource.contains("hello"))
        } else {
            XCTFail("Second block should be pendingCode, got \(parsed.blocks[1])")
        }
    }

    func testClosedCodeFencePromotesToCodeBlockNotPending() {
        let complete = """
        ```swift
        print("hi")
        ```
        """
        let parsed = WarRoomChatStreamParser.parse(complete)
        XCTAssertEqual(parsed.blocks.count, 1)
        if case .code(let language, let source) = parsed.blocks.first {
            XCTAssertEqual(language, "swift")
            XCTAssertEqual(source.trimmingCharacters(in: .whitespacesAndNewlines), "print(\"hi\")")
        } else {
            XCTFail("Closed fence must be finished code, got \(parsed.blocks)")
        }
    }

    func testUnclosedThinkTagKeepsAnswerEmptyAndReasoningOpen() {
        let text = "<think>chain of thought still running"
        let parsed = WarRoomChatStreamParser.parse(text)
        XCTAssertTrue(parsed.isReasoningOpen)
        XCTAssertEqual(parsed.reasoning, "chain of thought still running")
        XCTAssertTrue(parsed.blocks.isEmpty, "Answer body must stay empty until </think> arrives.")
    }

    func testClosedThinkTagYieldsReasoningPlusBody() {
        let text = "<think>internal notes</think>Visible answer."
        let parsed = WarRoomChatStreamParser.parse(text)
        XCTAssertFalse(parsed.isReasoningOpen)
        XCTAssertEqual(parsed.reasoning, "internal notes")
        XCTAssertEqual(parsed.blocks.count, 1)
        if case .markdown(let body) = parsed.blocks.first {
            XCTAssertEqual(body, "Visible answer.")
        } else {
            XCTFail("Body should render as markdown.")
        }
    }

    func testTypedChartFenceProducesChartBlockWhenPayloadValidates() {
        let text = """
        ```thoxchart
        {"kind":"bar","title":"Alerts","labels":["A","B"],"values":[1,2]}
        ```
        """
        let parsed = WarRoomChatStreamParser.parse(text)
        XCTAssertEqual(parsed.blocks.count, 1)
        if case .chart(let spec) = parsed.blocks.first {
            XCTAssertEqual(spec.kind, .bar)
            XCTAssertEqual(spec.title, "Alerts")
            XCTAssertEqual(spec.labels, ["A", "B"])
            XCTAssertEqual(spec.values, [1, 2])
        } else {
            XCTFail("Valid thoxchart payload should promote to a chart block, got \(parsed.blocks)")
        }
    }

    func testMalformedChartPayloadFallsBackToCodeBlockRatherThanBeingDropped() {
        let text = """
        ```thoxchart
        not-json
        ```
        """
        let parsed = WarRoomChatStreamParser.parse(text)
        XCTAssertEqual(parsed.blocks.count, 1)
        if case .code(let language, let source) = parsed.blocks.first {
            XCTAssertEqual(language, "thoxchart")
            XCTAssertTrue(source.contains("not-json"))
        } else {
            XCTFail("Invalid payload must degrade to a code block, got \(parsed.blocks)")
        }
    }
}

// MARK: - Test doubles

/// Transport that reports ready but never emits — lets tests exercise the
/// "user submits, no reply arrives" path deterministically.
private struct StubTransport: ChatTransport {
    var engineLabel: String { "stub" }
    var isReady: Bool { true }
    var unavailableReason: String? { nil }

    func stream(history: [ChatExchange], options: ChatGenerationOptions) -> AsyncStream<ChatStreamEvent> {
        AsyncStream { continuation in
            continuation.yield(.completed)
            continuation.finish()
        }
    }
}

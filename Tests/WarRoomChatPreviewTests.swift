import XCTest
import WarRoomCore
import WarRoomOpenWebUI
@testable import ThoxWarRoom

@MainActor
final class WarRoomChatPreviewTests: XCTestCase {

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
        XCTAssertTrue(spec.source.contains("Counter"), "Bundled artifact HTML should render the counter dashboard.")
        // No external network references — the artifact must be renderable offline.
        XCTAssertFalse(spec.source.lowercased().contains("http://"))
        XCTAssertFalse(spec.source.lowercased().contains("https://"))
    }

    // MARK: - Evidence-gated composer

    func testFreshModelExposesFailClosedContract() {
        let model = WarRoomChatPreviewModel(
            workspaceLabel: "Research",
            boundaryLabel: "Private network"
        )

        XCTAssertFalse(model.contract.isAvailable)
        XCTAssertEqual(model.contract.blocker, .authenticatedCaptureRequired)
        XCTAssertTrue(model.isEvidenceBannerVisible)
        XCTAssertEqual(model.composerActionLabel, "Preview")
    }

    func testMissingEvidenceListMatchesProviderContract() {
        let model = WarRoomChatPreviewModel(
            workspaceLabel: "Research",
            boundaryLabel: "Private network"
        )

        let requirementSet = Set(model.missingEvidence)

        XCTAssertEqual(requirementSet, OpenWebUIProvider.nativeChatContract.missingEvidence)
        // The presentation list is deterministic — future test failures should
        // be a signal that the ordering shifted, not that the set changed.
        XCTAssertEqual(model.missingEvidence.first, .credentialLifecycle)
        XCTAssertEqual(model.missingEvidence.last, .sourceCitations)
    }

    // MARK: - Composer semantics

    func testEmptyOrWhitespaceDraftDoesNotAppendTurn() {
        let model = WarRoomChatPreviewModel(
            workspaceLabel: "Research",
            boundaryLabel: "Private network"
        )
        let baseline = model.turns.count

        model.draft = "   \n\t"
        model.submitDraft()

        XCTAssertEqual(model.turns.count, baseline)
        XCTAssertFalse(model.canSubmit)
    }

    func testSubmitDraftAppendsUserTurnAndClearsComposer() {
        let model = WarRoomChatPreviewModel(
            workspaceLabel: "Research",
            boundaryLabel: "Private network",
            seed: []
        )

        model.draft = "Hello ThoxOS"
        XCTAssertTrue(model.canSubmit)

        model.submitDraft()

        XCTAssertEqual(model.turns.count, 1)
        XCTAssertEqual(model.turns.first?.role, .user)
        if case let .markdown(text) = model.turns.first?.blocks.first {
            XCTAssertEqual(text, "Hello ThoxOS")
        } else {
            XCTFail("User turn should be a single markdown block.")
        }
        XCTAssertTrue(model.draft.isEmpty)
    }

    func testRestoreGoldenReplacesTranscriptWithFixture() {
        let model = WarRoomChatPreviewModel(
            workspaceLabel: "Research",
            boundaryLabel: "Private network"
        )
        model.draft = "extra prompt"
        model.submitDraft()
        XCTAssertGreaterThan(model.turns.count, ChatFixture.goldenTranscript.count)

        model.restoreGolden()

        XCTAssertEqual(model.turns.count, ChatFixture.goldenTranscript.count)
        XCTAssertTrue(model.draft.isEmpty)
        XCTAssertEqual(model.turns.first?.role, .user)
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

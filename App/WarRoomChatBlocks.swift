// WarRoomChatBlocks.swift
// Typed block contract for the ThoxOS chat surface, mirroring the golden
// reference in `docs/fixtures/current-service-contracts/chat-ux-golden.html`
// (F1–F6). These types are the *presentation* contract — they describe what a
// finished message looks like to the renderer, independent of any provider
// transport. The provider transport for live chat remains fail-closed behind
// `OpenWebUIProvider.nativeChatContract` (WR-004) until authenticated evidence
// is captured, but the presentation layer can be built and reviewed today.
//
// Type discriminators match the wire contract in the golden reference so a
// future native transport can hydrate blocks from the same JSON shape without
// a renaming pass.

import Foundation

/// One typed presentation unit inside an assistant message.
///
/// Every case corresponds to one row/card in the ThoxOS chat golden reference
/// (F1 Markdown/code/math, F2 Chart, F2 Mermaid, F3 Artifact card, F5 Sandpack,
/// F6 Digital Human turn).
enum ThoxBlock: Equatable, Hashable {
    /// Prose written in restricted inline Markdown (bold/italic/inline code
    /// and inline math). Block Markdown is deliberately not accepted here —
    /// fences are their own block so a partially streamed code segment cannot
    /// desynchronize a second parser.
    case markdown(String)

    /// A finished, language-tagged code block.
    case code(language: String, source: String)

    /// A code fence that has been opened by the stream but not yet closed.
    /// Rendered distinctly from `.code` (no copy affordance, explicit "receiving"
    /// chrome) so a half-arrived block is never mistaken for a finished one the
    /// user can act on.
    case pendingCode(language: String, partial: String)

    /// A time-series chart with a title and paired labels/values.
    case chart(ChartSpec)

    /// A Mermaid graph source. Rendered as a labeled, monospaced fallback so
    /// the native surface does not have to ship a JavaScript runtime.
    case mermaid(source: String)

    /// A reference to a self-contained HTML artifact, opened in a side panel
    /// / fullscreen sheet.
    case artifact(ArtifactSpec)

    /// An editable multi-file live-code surface (index.html + script.js). In
    /// the preview it is rendered read-only until a durable-fixture runtime
    /// review confirms a bounded sandbox.
    case sandpack(SandpackSpec)

    /// A Digital Human turn — a named persona paused at an approval boundary
    /// or actively running an approved bounded action.
    case digitalHuman(DigitalHumanSpec)

    /// Stable identity for `ForEach`/diff purposes.
    var kindIdentifier: String {
        switch self {
        case .markdown: return "markdown"
        case .code: return "code"
        case .pendingCode: return "pendingCode"
        case .chart: return "chart"
        case .mermaid: return "mermaid"
        case .artifact: return "artifact"
        case .sandpack: return "sandpack"
        case .digitalHuman: return "digitalHuman"
        }
    }
}

/// Chart payload matching the golden reference (`chart`, `title`, `labels`,
/// `values`).
struct ChartSpec: Equatable, Hashable {
    enum Kind: String, Equatable, Hashable, CaseIterable {
        case line
        case bar
    }

    let kind: Kind
    let title: String
    let labels: [String]
    let values: [Double]
}

/// Reference to a bundled artifact HTML fixture rendered by the artifact panel.
struct ArtifactSpec: Equatable, Hashable {
    let artifactID: String
    let title: String
    /// The runtime hint (`html`, `svg`, `image`) matches the golden reference.
    let kind: String
    /// Bundled source. For the preview surface these are static fixtures owned
    /// by the app; a future live transport supplies its own text.
    let source: String
}

/// Sandpack payload: named files keyed by file name.
struct SandpackSpec: Equatable, Hashable {
    let template: String
    /// File names in stable declared order.
    let fileOrder: [String]
    /// File name → source text.
    let files: [String: String]
}

/// One Digital Human turn — persona + status + prose.
struct DigitalHumanSpec: Equatable, Hashable {
    enum Status: String, Equatable, Hashable {
        case running
        case awaitingApproval = "awaiting_approval"
        case complete
    }

    let persona: String
    let status: Status
    let text: String
}

/// A single conversational turn rendered by the block transcript.
struct ChatTurn: Identifiable, Equatable, Hashable {
    enum Role: Equatable, Hashable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    /// User turns collapse to a single markdown block; assistant turns can be
    /// a heterogeneous sequence.
    let blocks: [ThoxBlock]

    init(id: UUID = UUID(), role: Role, blocks: [ThoxBlock]) {
        self.id = id
        self.role = role
        self.blocks = blocks
    }
}

/// The immutable golden-message fixture. Ported from the reference HTML file
/// character-for-character so the two surfaces render the same content.
enum ChatFixture {
    /// The seven-block "golden message" from the reference file.
    static let goldenAssistantBlocks: [ThoxBlock] = [
        .markdown(
            """
            **ThoxOS chat** renders a typed block stream. This paragraph is Markdown with a list, an inline `code` span, and math:

            - sanitized HTML (DOMPurify)
            - syntax-highlighted code
            - KaTeX: ∫₀¹ x² dx = 1⁄3
            """
        ),
        .code(
            language: "typescript",
            source: """
            // F1 — highlighted, copyable
            async function ask(q: string) {
              const r = await ox.chat([{ role: 'user', content: q }], { reasoning: true });
              return r.content;
            }
            """
        ),
        .chart(
            ChartSpec(
                kind: .line,
                title: "Fleet tokens / hr",
                labels: ["Mon", "Tue", "Wed", "Thu", "Fri"],
                values: [12, 19, 15, 27, 32]
            )
        ),
        .mermaid(source: "graph LR; U[User]-->C[ThoxOS Chat]; C-->R[ThoxRoute]; R-->O[ox-alpha]; R-->L[Local model]"),
        .artifact(
            ArtifactSpec(
                artifactID: "a1",
                title: "Counter dashboard",
                kind: "html",
                source: ChatFixture.artifactCounterHTML
            )
        ),
        .sandpack(
            SandpackSpec(
                template: "vanilla",
                fileOrder: ["index.html", "script.js"],
                files: [
                    "index.html": "<h2 style='font-family:system-ui'>Edit me →</h2>\n<button id=b>Tap</button>",
                    "script.js": "document.getElementById('b').onclick=()=>alert('ThoxOS Sandpack live!')"
                ]
            )
        ),
        .digitalHuman(
            DigitalHumanSpec(
                persona: "Victoria",
                status: .awaitingApproval,
                text: "Drafting the launch reply and classifying 3 inbox threads. Crossing an external boundary (send) will pause for your approval."
            )
        )
    ]

    /// Bundled artifact HTML. Rendered by the artifact panel in a WKWebView
    /// backed by a nonpersistent data store with all network navigation
    /// canceled by the coordinator (see `SafeArtifactWebView`).
    static let artifactCounterHTML: String = """
    <!doctype html><html><head><meta charset=utf-8><style>
      body{margin:0;font:14px system-ui;background:#0b0d10;color:#e7edf3;display:grid;place-items:center;height:100vh}
      .card{padding:24px 28px;border:1px solid #05A451;border-radius:16px;text-align:center}
      h1{margin:.2em 0;background:linear-gradient(90deg,#05A451,#0bd06a);-webkit-background-clip:text;color:transparent}
      button{margin-top:12px;background:#05A451;border:0;color:#fff;padding:8px 16px;border-radius:9px;cursor:pointer}
    </style></head><body><div class=card><h1 id=n>0</h1><div>ThoxOS artifact — live HTML</div>
    <button onclick="document.getElementById('n').textContent=+document.getElementById('n').textContent+1">Increment</button>
    </div></body></html>
    """

    /// The one-line user prompt shown before the assistant fixture.
    static let goldenUserPrompt: String = "Show me every block type on the ThoxOS chat surface."

    /// Full seed transcript used by the preview model.
    static var goldenTranscript: [ChatTurn] {
        [
            ChatTurn(role: .user, blocks: [.markdown(goldenUserPrompt)]),
            ChatTurn(role: .assistant, blocks: goldenAssistantBlocks)
        ]
    }
}

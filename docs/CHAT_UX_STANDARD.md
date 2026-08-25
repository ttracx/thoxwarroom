# ThoxOS chat UX standard

Last updated: 2026-08-25

This document is the contract between the three THOX chat surfaces. It exists
because the golden fixture footer points at it, and because the native surface
now deliberately diverges from that fixture in a few places — every divergence
below is a decision, not drift.

## The three sources, and which one wins

| Source | Owns | Authority |
|---|---|---|
| `docs/fixtures/current-service-contracts/chat-ux-golden.html` | The **wire contract** — the `blocks[]` array, its `type` discriminators, and the six target interactions F1–F6 | Authoritative for *what* a message can contain |
| ThoxMythos-9B Space (`web/components/chat/*`, `web/app/globals.css`) | The **visual language** — palette, spacing, chrome, composer, message anatomy | Authoritative for *how* it looks and behaves |
| `thoxos-ios` `Sources/ThoxDesign/ThoxTokens.swift` (generated) | The **token table** | Authoritative for exact colour values |

Where the golden fixture and ThoxMythos disagree, **ThoxMythos wins** and the
divergence is recorded in "Deliberate divergences" below. The fixture is frozen
by SHA-256 and is a wire/interaction reference, not a colour authority.

Reference SHA-256, asserted by `scripts/verify_chat_ux_parity.py`:

```text
86bdce5a7206ac2ce0b9191db4bf412508a3d5bb3c43aeb180fc267e33a674cd
```

## Block contract

Seven block types make up an assistant message. The Swift discriminators in
`ThoxBlock.kindIdentifier` map one-to-one onto the reference `type` field.

| Reference `type` | Swift case | Native renderer | Notes |
|---|---|---|---|
| `markdown` | `.markdown(String)` | `ThoxMarkdownBody` | Block structure segmented natively; leaves parsed inline-only |
| `code` | `.code(language:source:)` | `ThoxHighlightedCodeBody` | Highlighted by `ThoxSyntaxHighlighter` |
| — | `.pendingCode(language:partial:)` | `PendingCodeBlockView` | Native-only. An unterminated fence mid-stream. Never re-classified as prose |
| `chart` | `.chart(ChartSpec)` | `ChartBlockView` | Swift Charts; VoiceOver reads every plotted value |
| `mermaid` | `.mermaid(source:)` | `ThoxMermaidBody` | Native layered flowchart, source pane fallback |
| `artifact` | `.artifact(ArtifactSpec)` | `ArtifactCardView` + `ArtifactPanel` | Preview/Code tabs, fullscreen |
| `sandpack` | `.sandpack(SandpackSpec)` | `ThoxSandpackBody` | Editable, live preview |
| `dh_turn` | `.digitalHuman(DigitalHumanSpec)` | `DigitalHumanBlockView` | Persona, status pill, pulsing dot |

`scripts/verify_chat_ux_parity.py` asserts that every `ThoxBlock` case has a
renderer arm and that the Swift fixture's block order matches the reference's,
block for block.

## Tokens

The palette is fleet-canonical, not per-app. `App/ThoxTheme.swift` carries it
and the verifier asserts each value.

| Token | Value | Role |
|---|---|---|
| `accent` | `#10B981` | Brand emerald. Primary actions, accents, list markers |
| `accentLight` | `#34D399` | Hover, string literals, "open" affordances |
| `accentDeep` | `#059669` | Pressed states, avatar gradient terminus |
| `background` | `#09090B` | App background |
| `surface` | `#18181B` | Cards, message containers |
| `elevated` | `#27272A` | Above `surface` |
| `codeBackground` | `#0D1117` | Code, chart, diagram, and preview wells |
| `separator` | `#27272A` | Hairlines |
| `borderStrong` | `#3F3F46` | Borders on anything interactive |
| `primaryText` | `#FAFAFA` | Body |
| `secondaryText` | `#A1A1AA` | Supporting copy |
| `faintText` | `#71717A` | Metadata and chrome captions. Never essential copy |
| `warning` | `#F59E0B` | In-flight |
| `danger` | `#EF4444` | Failure |

`chatMaxWidth` is 768pt, matching the web `max-w-3xl` and the iOS
`Size.chatMaxWidth`.

**History.** This file previously carried a fork of the palette — accent
`#05A451`, background `#0C0E12`, surface `#161A20` — that matched no shipping
THOX surface. It was corrected on 2026-08-25. Do not reintroduce it. The frozen
golden fixture still contains the old hexes; that is expected, and is why the
fixture is not the colour authority.

## Message anatomy

**Assistant turn.** Emerald left rail, `TX` avatar, blocks stacked at 12pt, then
an always-visible action row (copy response + block count).

The action row is always visible rather than hover-revealed. ThoxMythos reveals
it on `group-hover`; hover is not a gesture that exists on iOS, and a control
the operator cannot find is a control that does not exist.

**User turn.** Right-aligned, capped at 520pt, `surface` fill, `borderStrong`
outline.

**Composer.** Engine picker row, growing field (`Ask anything…`, 1–6 lines),
Send↔Stop swap mid-stream, New chat and Reset affordances, and one line of
honest helper text stating whether a model will actually be contacted.

**Empty state.** Product name, one sentence naming the workspace and its
boundary, four starters that *prefill* the composer rather than sending, and a
link back to the golden fixture.

## Deliberate divergences from the golden fixture

1. **Assistant container.** The fixture draws a bubble; ThoxMythos draws an
   emerald left rail. The native surface follows ThoxMythos.
2. **Mermaid.** The fixture runs mermaid.js. The native surface parses a bounded
   flowchart subset in Swift (`MermaidFlowchart`) and renders it with SwiftUI.
   Unsupported syntax falls back to a labelled source pane. Shipping a
   JavaScript diagram runtime inline in the transcript is out of scope for the
   audit boundary.
3. **Math.** The fixture uses KaTeX. The native fixture carries the same
   expression as Unicode (`∫₀¹ x² dx = 1⁄3`). A typed `math` block is the
   correct long-term answer and is not yet implemented.
4. **Syntax highlighting.** The fixture uses highlight.js, ThoxMythos uses
   Prism. The native surface uses `ThoxSyntaxHighlighter`, which is lossless by
   construction and tinted with the same One Dark palette.
5. **Digital Human status.** The fixture pins the persona at `running`. The
   native fixture uses `awaitingApproval`, which is what the accompanying prose
   actually describes. Both statuses render.
6. **Sandpack.** The fixture bundles its own preview; the native surface renders
   a document composed entirely on-device (`SandpackSpec.composedDocument`) in
   the same non-persistent, navigation-cancelling web view the artifact panel
   uses.

## Boundary rules

These are enforced, not aspirational. `scripts/verify_chat_ux_parity.py` fails
the build if any of them regress.

1. **No network API on the presentation path.** No file in `App/WarRoomChat*` or
   the three parsers may reference `URLSession`, `URLRequest`, `NWConnection`,
   or `CFStream`. Transport lives behind `ChatTransport`, in its own file,
   behind the WR-004 evidence gate.
2. **The parsers stay Foundation-only.** `ThoxMarkdownDocument`,
   `ThoxSyntaxHighlighter`, and `MermaidFlowchart` import nothing but
   `Foundation`. That is what makes them testable without a host app and what
   keeps a UI dependency from creeping into parsing.
3. **Composed documents reference nothing remote.** The artifact fixture and the
   Sandpack composition contain no `http://`, `https://`, or protocol-relative
   URL. The preview web view cancels every navigation, so a remote reference
   would render as a silent blank rather than a visible failure.
4. **Highlighting is lossless.** `tokenize(s, l).map(\.text).joined() == s` for
   every input and language. A code block the operator copies must be identical
   to what the model produced.
5. **The gate is legible.** While `OpenWebUIProvider.nativeChatContract` is
   closed, the surface names the blocker and lists the exact missing evidence.
   It never shows a Send button that silently drops the request.

## Verification

```bash
# Runs anywhere, no Swift toolchain required.
python3 scripts/verify_chat_ux_parity.py --verbose

# Requires macOS + Xcode.
xcodebuild test -scheme "ThoxWarRoom macOS" -destination "platform=macOS"
```

The Python verifier carries line-for-line ports of the markdown and mermaid
parsers so their behaviour can be exercised off a Mac. If a port and its Swift
original ever disagree, one of them is wrong — that disagreement is the finding,
and the fix is never to relax the check.

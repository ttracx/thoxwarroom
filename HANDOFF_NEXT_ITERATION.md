# Handoff — next iteration

Date: 2026-08-25
Scope: ThoxOS chat surface (WR-017 / WR-018)
Audience: whoever picks this up next, human or agent

Read this first, then `docs/CHAT_UX_STANDARD.md`, then `development_queue.md`.

---

## 1. Read this before you touch anything

**Two agents worked this repository concurrently on 2026-08-25.** One built the
block surface, the incremental stream parser, the transport abstraction, and the
engine picker (recorded as WR-017). The other — this handoff — built the
rendering fidelity layer, corrected the token palette, and added toolchain-free
verification (WR-018).

The two workstreams were kept apart on purpose:

- WR-017 owns `WarRoomChatBlocks`, `…StreamParser`, `…Transport`,
  `…PreviewModel`, `…PreviewView`, `…PreviewHost`, `…ArtifactPanel`.
- WR-018 owns `ThoxTheme`, `ThoxMarkdownDocument`, `ThoxSyntaxHighlighter`,
  `MermaidFlowchart`, `WarRoomChatRichRenderers`, and
  `scripts/verify_chat_ux_parity.py`.

`WarRoomChatBlockRenderer.swift` is shared. It is now pure dispatch: one small
view per `ThoxBlock` case, each delegating to a body in
`WarRoomChatRichRenderers.swift`. **If you rewrite that file wholesale, re-apply
the four delegations** — `MarkdownBlockView → ThoxMarkdownBody`,
`CodeBlockView → ThoxHighlightedCodeBody`, `MermaidBlockView → ThoxMermaidBody`,
`SandpackBlockView → ThoxSandpackBody`. The verifier will not catch this; it
checks that every case has *an* arm, not which body it calls.

**Nothing in this iteration has been compiled.** No Swift toolchain was
available on the host. See §5 — that is the top-priority item, and it is not
optional.

---

## 2. What changed in this iteration (WR-018)

### 2.1 Token palette corrected to the fleet standard

`App/ThoxTheme.swift` carried a fork — accent `#05A451`, background `#0C0E12`,
surface `#161A20` — that matched neither the THOX brand system nor any shipping
surface. It now carries the canonical palette, cross-checked against three
independent owners: the brand system, the ThoxMythos-9B Space
(`web/app/globals.css`), and `thoxos-ios`'s generated `ThoxTokens.swift`.

Every previously existing symbol kept its name and role, so no call site
changed. Nine new tokens were added (`accentLight`, `accentDeep`, `elevated`,
`codeBackground`, `borderStrong`, `faintText`, `warning`, `danger`, plus the
metric constants). `Color(hex6:)` takes a packed `0xRRGGBB` literal so the table
diffs cleanly against the upstream CSS custom properties.

All four remaining hardcoded `Color(red:green:blue:)` literals on the chat path
were replaced with tokens.

### 2.2 Three Foundation-only parsers

These are new files. They import nothing but `Foundation`, have no UI
dependency, and are individually unit-testable.

| File | What it does | Why it exists |
|---|---|---|
| `App/ThoxMarkdownDocument.swift` | Segments block-level Markdown (headings, bullet/ordered lists, quotes, rules, paragraphs) | Inline-only `AttributedString` rendered the golden reference's bullet list as three lines starting with a hyphen. Both reference surfaces render a real list |
| `App/ThoxSyntaxHighlighter.swift` | Lossless tokenizer for swift/ts/js/python/bash/json/css + a tag-aware markup pass | Both reference surfaces highlight code. Shipping highlight.js or Prism means a script-executing web view inline in the transcript |
| `App/MermaidFlowchart.swift` | Bounded flowchart parser + longest-path layered layout | The previous fallback printed raw mermaid source. Honest, but the reader had to parse a graph in their head |

**The load-bearing invariant** is on the tokenizer:
`tokenize(s, l).map(\.text).joined() == s` for every input and language.
Highlighting may mis-colour; it may never lose, duplicate, or reorder a
character, because the operator copies these blocks. `WarRoomChatRenderingTests`
asserts this across fourteen deliberately hostile fixtures × ten languages.

### 2.3 Rich renderers

`App/WarRoomChatRichRenderers.swift`:

- **Markdown** renders real lists with emerald markers, headings, quotes with an
  emerald rail, and thematic breaks.
- **Code** gains a header bar (language, `plain` badge for unhighlightable
  languages, copy) and One Dark colouring.
- **Mermaid** renders a native layered diagram with a Diagram/Source toggle.
  Unsupported syntax degrades to a labelled source pane — deliberately, because
  a half-drawn diagram is worse than legible source. VoiceOver reads the edge
  list, which is the actual information content.
- **Sandpack** is now editable with a live preview, matching F5. The composed
  document is built on-device by `SandpackSpec.composedDocument(overriding:)`,
  which neutralises `</script>` inside the JS file and emits nothing remote.
- **Digital Human** uses the token palette, a motion-aware pulsing dot
  (suppressed under Reduce Motion), and status-coloured rail.

### 2.4 Empty state and turn actions

- Empty state with product name, an honest sentence naming the workspace and its
  boundary, four starters that **prefill** rather than send, and a link back to
  the golden fixture. Reached via a new "New chat" affordance.
- Always-visible copy-response row under each assistant turn. ThoxMythos
  reveals this on hover; hover is not a gesture that exists on iOS.
- `WarRoomChatPreviewModel` gained `startNewChat()` and `prefill(_:)`. The
  `plainText` projection on `[ThoxBlock]` was widened from `private` to internal
  so the copy affordance and the transport share exactly one implementation.

### 2.5 Verification without a toolchain

`scripts/verify_chat_ux_parity.py` — **58 checks, 0 findings as of this
handoff.** Runs on any host with Python 3.10+.

1. **Fixture parity.** Parses `blocks[]` out of the golden HTML and the
   `ChatFixture` literal out of Swift, compares block-for-block, and asserts the
   fixture's SHA-256 against the reviewed value.
2. **Renderer coverage.** Every `ThoxBlock` case has a `case` arm.
3. **Boundary.** No network API on the presentation path; the three parsers stay
   Foundation-only.
4. **Tokens.** Each canonical hex is present and bound to the right name.
5. **Delimiters.** String- and comment-aware brace/bracket/paren balance — the
   single most common way a hand-edited Swift file breaks when nobody can build.
6. **Algorithms.** Line-for-line Python ports of the markdown and mermaid
   parsers, exercised against the golden inputs, so parsing behaviour is proven
   before anyone opens Xcode.

The ports are a cross-check, not a second implementation. If a port and its
Swift original disagree, that disagreement is the finding — never a reason to
relax the check.

---

## 3. Run it

```bash
cd /path/to/thoxwarroom

# Anywhere:
python3 scripts/verify_chat_ux_parity.py --verbose
# → 58 checks passed, 0 findings

# macOS + Xcode only:
./scripts/bootstrap.sh          # checksum-pinned XcodeGen 2.46.0
xcodebuild test -scheme "ThoxWarRoom macOS" -destination "platform=macOS"
xcodebuild build -scheme "ThoxWarRoom iOS" \
  -destination "generic/platform=iOS Simulator"
```

New files are picked up automatically: `project.yml` globs `App/` and `Tests/`,
so no target edit is needed.

---

## 4. Files touched

**Added**

```
App/ThoxMarkdownDocument.swift
App/ThoxSyntaxHighlighter.swift
App/MermaidFlowchart.swift
App/WarRoomChatRichRenderers.swift
Tests/WarRoomChatRenderingTests.swift          (38 test methods)
scripts/verify_chat_ux_parity.py
docs/CHAT_UX_STANDARD.md
docs/fixtures/current-service-contracts/chat-ux-golden.html
docs/fixtures/current-service-contracts/chat-ux-golden.README.md
HANDOFF_NEXT_ITERATION.md
```

**Modified**

```
App/ThoxTheme.swift                 rewritten to the canonical palette
App/WarRoomChatBlockRenderer.swift  four bodies now delegate; DH restyled
App/WarRoomChatArtifactPanel.swift  hardcoded code-well colour → token
App/WarRoomChatPreviewView.swift    empty state, turn actions, New chat
App/WarRoomChatPreviewModel.swift   startNewChat, prefill, plainText widened
development_queue.md                WR-018 row + this iteration's section
```

The golden fixture was placed at the path the source comments already referenced
and its SHA-256 matches the value published in the supplied README —
`86bdce5a7206ac2ce0b9191db4bf412508a3d5bb3c43aeb180fc267e33a674cd`.

---

## 5. Do these next, in this order

### P0 — Compile and test on a Mac

Nothing here has been through a compiler. The verifier catches structural
breakage; it does not catch a type error. Expect to fix small things. Highest-risk
spots, in order:

1. `MermaidNodeView.outline` returns `AnyShape` from a `switch` — confirm
   `AnyShape` resolves on both deployment targets (iOS 16 / macOS 13 minimum;
   this project targets 17/14, so it should).
2. `ChartBlockView` puts a `switch` inside `Chart { }`. `ChartContentBuilder`
   has `buildEither`, so it should hold, but this is the least conventional
   construct in the diff.
3. `TextEditor(text:).scrollContentBackground(.hidden)` in `ThoxSandpackBody` —
   available on both targets, but verify the background actually clears on
   macOS.
4. `ChatCopyButton` uses `NSPasteboard`/`UIPasteboard` behind `canImport`
   guards; `WarRoomChatRichRenderers.swift` imports only `SwiftUI`. If the
   transitive AppKit/UIKit re-export does not carry them, add explicit guarded
   imports.

After it builds: re-run the verifier, run the full macOS suite, and record the
counts in `development_queue.md` the way every other row does.

### P1 — Close the remaining reference gaps

- **Typed `math` block.** The fixture's KaTeX expression is currently frozen as
  Unicode in the Swift fixture. A `.math(latex:)` case with a native renderer is
  the correct answer.
- **Streaming cadence.** `thoxos-ios` has `DemoTranscript.Pacing`
  (`chunk 3 / 28ms / firstToken 650ms`, plus `.instant` for UI tests). The
  scripted transport here should adopt the same numbers so demo footage matches
  across surfaces.
- **Route/provenance badge.** Every other THOX surface labels each assistant
  turn with where it was answered (`deviceLocal | lan | cloud | mesh | scripted`).
  This surface has an engine picker but no per-turn provenance. That labelling is
  a brand invariant; add it.

### P2 — Fleet consolidation

`thoxos-ios` already has `Sources/ThoxDesign` — a **generated** token package
(`node design-tokens/build.mjs` in `thoxos-webby-edition`, with a CI `--check`
that fails on drift). `App/ThoxTheme.swift` is now value-identical to it but is
still a hand-maintained copy, which is how this drifted the first time.

Either depend on `ThoxDesign` directly, or generate `ThoxTheme.swift` from the
same `thox-tokens.json` and add the `--check` to this repo's CI. Until one of
those lands, `scripts/verify_chat_ux_parity.py` is the only thing preventing a
recurrence.

Also worth folding in from `thoxos-ios`: the `AnswerParser` / `ReasoningSplit`
contract in `Sources/ThoxOSApp/Chat/CodePreviewView.swift`. It encodes two
hard-won streaming rules — never render an unclosed fence as a code block, and
run rich renderers only when `!isStreaming` — and it made the same positional
identity decision this surface did (`id: \.offset`, blocks not `Identifiable`).
`WarRoomChatStreamParser` and `AnswerParser` should converge rather than diverge.

Note: `thox-ondevice-ai` hardcodes its own private `Palette` in
`ThoxModelPickerView.swift` (emerald `#10B981`, amber `#F59E0B`, surface
`#18181B`). Values are right; the fork is not. Point it at the shared tokens.

### P3 — Still open from WR-017, unchanged

The remote provider transport stays fail-closed until the WR-004 authenticated
capture lands. `SafeArtifactWebView` needs a compiled content-rule list and a
per-origin isolated data store before it renders an *untrusted* live artifact —
today it only renders reviewed, bundled fixture HTML, which is what makes the
current containment sufficient.

---

## 6. Rules that must not be relaxed

If you find yourself editing one of these to make something pass, stop — the
thing you are trying to pass is the bug.

1. Tokenizer output is lossless.
2. No network API on the presentation path.
3. The three parsers import only `Foundation`.
4. Composed documents reference nothing remote.
5. The chat gate stays legible: while the contract is closed, the surface names
   the blocker and lists the exact missing evidence, and never shows a Send
   button that silently drops the request.
6. Unsupported diagram syntax falls back to labelled source. Never draw a
   partial graph.

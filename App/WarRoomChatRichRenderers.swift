// WarRoomChatRichRenderers.swift
// Rich native renderers for the ThoxOS chat surface: structured Markdown,
// syntax-highlighted code, native Mermaid flowcharts, and an editable Sandpack
// surface.
//
// WHY THESE LIVE IN THEIR OWN FILE
// --------------------------------
// `WarRoomChatBlockRenderer.swift` owns *dispatch* — one small view per
// `ThoxBlock` case. The bodies below are the expensive part, and keeping them
// separate means the dispatch file stays reviewable and the rich renderers can
// be adopted, reverted, or unit-tested one at a time. Each `…BlockView` in the
// dispatch file delegates to exactly one type here.
//
// The parsing these views depend on lives in three Foundation-only files with
// no UI dependency, so all of it is testable without a host app:
//   * `ThoxMarkdownDocument`   — block-level Markdown segmentation
//   * `ThoxSyntaxHighlighter`  — lossless code tokenizer
//   * `MermaidFlowchart`       — bounded flowchart parser + layered layout
//
// Nothing here performs I/O. The one web view (`SafeArtifactWebView`, owned by
// `WarRoomChatArtifactPanel.swift`) renders a locally composed document through
// a non-persistent data store whose navigation delegate cancels every request
// other than the initial `about:blank` seed.

import SwiftUI

// MARK: - Shared chrome

/// The uppercase mono caption that labels every non-prose block. Mirrors
/// `.block-title` in `chat-ux-golden.html` and the header rows on the shipping
/// ThoxMythos artifact and code cards.
struct ChatBlockCaption: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
                    .foregroundStyle(ThoxTheme.accent)
            }
            Text(text.uppercased())
                .font(.caption2.monospaced().weight(.semibold))
                .kerning(0.8)
                .foregroundStyle(ThoxTheme.faintText)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// A rounded well carrying the standard chat block border and code background.
struct ChatBlockWell<Content: View>: View {
    var fill: Color = ThoxTheme.codeBackground
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: ThoxTheme.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ThoxTheme.controlRadius)
                    .stroke(ThoxTheme.borderStrong, lineWidth: 1)
            }
    }
}

/// Copy-to-clipboard control with a 1.4s confirmation.
///
/// Public (not `private`) because the transcript also offers a whole-turn copy,
/// and both must behave identically.
struct ChatCopyButton: View {
    let text: String
    var label: String = "Copy"

    @State private var didCopy = false

    var body: some View {
        Button {
            Self.copy(text)
            didCopy = true
            Task {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                didCopy = false
            }
        } label: {
            Label(didCopy ? "Copied" : label, systemImage: didCopy ? "checkmark" : "doc.on.doc")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(didCopy ? ThoxTheme.accentLight : ThoxTheme.secondaryText)
        .accessibilityLabel(didCopy ? "Copied to clipboard" : label)
    }

    /// Writes to the platform pasteboard.
    static func copy(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}

/// One run of inline Markdown — bold, italic, links, inline code.
///
/// Block syntax never reaches here; `ThoxMarkdownDocument` has already removed
/// it. Parse failure falls back to the literal text, so a malformed span can
/// never blank a message.
struct InlineMarkdownText: View {
    private let source: String

    init(_ source: String) {
        self.source = source
    }

    var body: some View {
        Text(attributed)
            .font(.body)
            .foregroundStyle(ThoxTheme.primaryText)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        (try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(
                allowsExtendedAttributes: false,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(source)
    }
}

// MARK: - Markdown body (F1)

/// Renders block-level Markdown natively: headings, bullet and ordered lists,
/// block quotes, thematic breaks, and paragraphs.
///
/// This is the fix for the most visible parity gap against both reference
/// surfaces. Inline-only parsing renders `- item` as the literal characters
/// `- item`; the golden reference renders a real `<ul>`, and ThoxMythos styles
/// one with emerald markers (`.thox-prose li::marker { color: var(--thox-brand) }`).
struct ThoxMarkdownBody: View {
    let text: String

    private var document: ThoxMarkdownDocument { ThoxMarkdownDocument.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(document.nodes.enumerated()), id: \.offset) { _, node in
                view(for: node)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for node: ThoxMarkdownDocument.Node) -> some View {
        switch node {
        case .paragraph(let value):
            InlineMarkdownText(value)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .heading(let level, let value):
            InlineMarkdownText(value)
                .font(Self.headingFont(level))
                .padding(.top, level <= 2 ? 6 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow(marker: "•", item: item)
                }
            }
            .accessibilityIdentifier("chat-block-markdown-list")

        case .orderedList(let start, let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                    listRow(marker: "\(start + offset).", item: item)
                }
            }
            .accessibilityIdentifier("chat-block-markdown-ordered-list")

        case .blockQuote(let paragraphs):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(ThoxTheme.accent)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        InlineMarkdownText(paragraph)
                            .foregroundStyle(ThoxTheme.secondaryText)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("chat-block-markdown-quote")

        case .thematicBreak:
            Rectangle()
                .fill(ThoxTheme.separator)
                .frame(height: 1)
                .padding(.vertical, 4)
                .accessibilityHidden(true)
        }
    }

    private func listRow(marker: String, item: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker)
                .font(.callout.monospaced())
                .foregroundStyle(ThoxTheme.accent)
                .frame(minWidth: 14, alignment: .trailing)
                .accessibilityHidden(true)
            InlineMarkdownText(item)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2.weight(.bold)
        case 2: return .title3.weight(.semibold)
        case 3: return .headline
        default: return .subheadline.weight(.semibold)
        }
    }
}

// MARK: - Highlighted code body (F1)

/// Syntax-highlighted, copyable code well.
struct ThoxHighlightedCodeBody: View {
    let language: String
    let source: String

    var body: some View {
        ChatBlockWell {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider().overlay(ThoxTheme.borderStrong)
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(Self.highlighted(source, language: language))
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(minWidth: 0, alignment: .leading)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(language.uppercased())
                .font(.caption2.monospaced().weight(.semibold))
                .kerning(0.8)
                .foregroundStyle(ThoxTheme.faintText)
            if !ThoxSyntaxHighlighter.isHighlightable(language) {
                Text("plain")
                    .font(.caption2.monospaced())
                    .foregroundStyle(ThoxTheme.faintText.opacity(0.7))
            }
            Spacer(minLength: 8)
            ChatCopyButton(text: source)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ThoxTheme.surface.opacity(0.7))
    }

    /// Maps tokenizer output onto colours.
    ///
    /// The tokenizer guarantees that the joined token text equals the source, so
    /// this pass can restyle code but can never drop or reorder it.
    static func highlighted(_ source: String, language: String) -> AttributedString {
        var result = AttributedString()
        for token in ThoxSyntaxHighlighter.tokenize(source, language: language) {
            var run = AttributedString(token.text)
            run.foregroundColor = color(for: token.kind)
            result.append(run)
        }
        return result
    }

    /// One Dark palette, matching the `oneDark` Prism theme the ThoxMythos web
    /// surface re-tints onto THOX surfaces.
    static func color(for kind: ThoxSyntaxHighlighter.TokenKind) -> Color {
        switch kind {
        case .plain: return ThoxTheme.primaryText
        case .comment: return ThoxTheme.faintText
        case .string: return ThoxTheme.accentLight
        case .number: return Color(hex6: 0xD19A66)
        case .keyword: return Color(hex6: 0xC678DD)
        case .type: return Color(hex6: 0x61AFEF)
        case .punctuation: return ThoxTheme.secondaryText
        }
    }
}

// MARK: - Mermaid body (F2)

/// Native Mermaid rendering with an explicit source fallback.
///
/// When `MermaidFlowchart.parse` returns `nil` the view shows the labelled
/// source pane instead. That degradation is deliberate: a half-drawn diagram is
/// worse than legible source, and the label tells the reader which one they are
/// looking at.
struct ThoxMermaidBody: View {
    let source: String

    @State private var showsSource = false

    private var flowchart: MermaidFlowchart? { MermaidFlowchart.parse(source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ChatBlockCaption(
                    text: "diagram · mermaid",
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                Spacer(minLength: 8)
                if flowchart != nil {
                    Button(showsSource ? "Diagram" : "Source") { showsSource.toggle() }
                        .buttonStyle(.borderless)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ThoxTheme.secondaryText)
                        .accessibilityIdentifier("chat-block-mermaid-toggle")
                }
                ChatCopyButton(text: source)
            }

            ChatBlockWell {
                Group {
                    if let flowchart, !showsSource {
                        MermaidFlowchartView(flowchart: flowchart)
                            .padding(14)
                    } else {
                        sourcePane
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var sourcePane: some View {
        VStack(alignment: .leading, spacing: 6) {
            if flowchart == nil {
                Text("Unsupported diagram syntax — showing source")
                    .font(.caption2)
                    .foregroundStyle(ThoxTheme.faintText)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(source)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(ThoxTheme.primaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minWidth: 0, alignment: .leading)
            }
        }
        .padding(12)
    }
}

/// Layered flowchart layout. Ranks advance along the declared axis; nodes
/// within a rank stack across it. Connectors are chevrons between ranks rather
/// than routed splines — enough to read the topology, cheap enough to lay out
/// inside a scrolling transcript.
struct MermaidFlowchartView: View {
    let flowchart: MermaidFlowchart

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            layout
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenSummary)
        .accessibilityIdentifier("chat-block-mermaid-diagram")
    }

    @ViewBuilder
    private var layout: some View {
        let ranks = flowchart.ranks
        if flowchart.direction.isHorizontal {
            HStack(alignment: .center, spacing: 10) {
                ForEach(Array(ranks.enumerated()), id: \.offset) { offset, rank in
                    if offset > 0 { connector }
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(rank) { node in
                            MermaidNodeView(node: node)
                        }
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(ranks.enumerated()), id: \.offset) { offset, rank in
                    if offset > 0 { connector }
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(rank) { node in
                            MermaidNodeView(node: node)
                        }
                    }
                }
            }
        }
    }

    private var connector: some View {
        Image(systemName: flowchart.direction.isHorizontal ? "chevron.right" : "chevron.down")
            .font(.caption.weight(.bold))
            .foregroundStyle(ThoxTheme.accent)
            .accessibilityHidden(true)
    }

    /// VoiceOver reads the edge list, which carries the actual information.
    private var spokenSummary: String {
        let edges = flowchart.edges.map { edge -> String in
            let from = flowchart.node(id: edge.from)?.label ?? edge.from
            let to = flowchart.node(id: edge.to)?.label ?? edge.to
            if let label = edge.label, !label.isEmpty {
                return "\(from) to \(to) via \(label)"
            }
            return "\(from) to \(to)"
        }
        return "Flow diagram. " + edges.joined(separator: ". ")
    }
}

private struct MermaidNodeView: View {
    let node: MermaidFlowchart.Node

    var body: some View {
        Text(node.label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(ThoxTheme.primaryText)
            .lineLimit(2)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(ThoxTheme.surface, in: outline)
            .overlay { outline.stroke(ThoxTheme.accent.opacity(0.55), lineWidth: 1) }
            .fixedSize(horizontal: false, vertical: true)
    }

    /// `AnyShape` keeps the outlines in one property without a generic
    /// explosion at the call site. It requires iOS 16 / macOS 13, both below
    /// this project's deployment targets.
    private var outline: AnyShape {
        switch node.shape {
        case .rectangle: return AnyShape(RoundedRectangle(cornerRadius: 4))
        case .rounded, .diamond: return AnyShape(RoundedRectangle(cornerRadius: 10))
        case .stadium, .circle: return AnyShape(Capsule())
        }
    }
}

// MARK: - Sandpack body (F5)

/// The composed single-file document for a Sandpack spec.
extension SandpackSpec {
    /// Key of the HTML entry point, if the spec declares one.
    static let htmlEntry = "index.html"
    /// Key of the script entry point, if the spec declares one.
    static let scriptEntry = "script.js"

    /// Builds the document the live preview renders.
    ///
    /// Two properties matter:
    ///   1. A `</script>` sequence inside the JS file is neutralised, so a
    ///      script file cannot close its own tag and inject markup.
    ///   2. The result is a complete standalone document with no external
    ///      references, so the preview web view never needs network access —
    ///      which is what lets its navigation delegate cancel everything.
    func composedDocument(overriding overrides: [String: String]? = nil) -> String {
        let resolved = overrides ?? files
        let html = resolved[Self.htmlEntry] ?? ""
        let script = (resolved[Self.scriptEntry] ?? "")
            .replacingOccurrences(of: "</script", with: "<\\/script")

        var document = """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body{margin:0;padding:14px;background:#0d1117;color:#fafafa;
            font:14px -apple-system,BlinkMacSystemFont,system-ui,sans-serif}
          button{background:#10b981;border:0;color:#04110b;padding:8px 14px;
            border-radius:9px;font-weight:600;cursor:pointer}
        </style></head><body>
        """
        document += "\n" + html + "\n"
        if !script.isEmpty {
            document += "<script>\n" + script + "\n</script>\n"
        }
        document += "</body></html>"
        return document
    }
}

/// Editable multi-file live-code surface.
///
/// F5 in the golden reference is *editable*: typing in a file re-renders the
/// preview. The native surface matches that, inside the same containment the
/// artifact panel uses — a non-persistent web view whose navigation delegate
/// cancels every request other than the initial `about:blank` seed, rendering a
/// document that is composed entirely on-device and references nothing remote.
struct ThoxSandpackBody: View {
    let spec: SandpackSpec

    @State private var files: [String: String] = [:]
    @State private var activeFile: String = ""
    @State private var renderedDocument: String = ""

    private var resolvedActiveFile: String {
        activeFile.isEmpty ? (spec.fileOrder.first ?? "") : activeFile
    }

    private var workingFiles: [String: String] {
        files.isEmpty ? spec.files : files
    }

    private var isDirty: Bool { !files.isEmpty && files != spec.files }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ChatBlockWell {
                VStack(alignment: .leading, spacing: 0) {
                    tabBar
                    Divider().overlay(ThoxTheme.borderStrong)
                    editor
                    Divider().overlay(ThoxTheme.borderStrong)
                    preview
                }
            }
        }
        .onAppear(perform: seedIfNeeded)
    }

    private var header: some View {
        HStack(spacing: 8) {
            ChatBlockCaption(text: "sandpack · \(spec.template)", systemImage: "curlybraces")
            Spacer(minLength: 8)
            if isDirty {
                Button("Reset", action: reset)
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ThoxTheme.secondaryText)
                    .accessibilityIdentifier("chat-block-sandpack-reset")
            }
            Button(action: run) {
                Label("Run", systemImage: "play.fill")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(ThoxTheme.accentLight)
            .accessibilityIdentifier("chat-block-sandpack-run")
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(spec.fileOrder, id: \.self) { file in
                Button {
                    activeFile = file
                } label: {
                    Text(file)
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(
                            file == resolvedActiveFile ? ThoxTheme.accentLight : ThoxTheme.faintText
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(file == resolvedActiveFile ? ThoxTheme.accent : .clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(file)
                .accessibilityAddTraits(file == resolvedActiveFile ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .background(ThoxTheme.surface.opacity(0.7))
    }

    private var editor: some View {
        TextEditor(text: binding(for: resolvedActiveFile))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(ThoxTheme.primaryText)
            .scrollContentBackground(.hidden)
            .background(ThoxTheme.codeBackground)
            .frame(height: 170)
            .padding(.horizontal, 6)
            .accessibilityIdentifier("chat-block-sandpack-editor")
            .accessibilityLabel("Editor for \(resolvedActiveFile)")
    }

    private var preview: some View {
        SafeArtifactWebView(html: renderedDocument)
            .frame(height: 170)
            .accessibilityIdentifier("chat-block-sandpack-preview")
            .accessibilityLabel("Live preview")
    }

    private func binding(for file: String) -> Binding<String> {
        Binding(
            get: { workingFiles[file] ?? "" },
            set: { newValue in
                if files.isEmpty { files = spec.files }
                files[file] = newValue
            }
        )
    }

    private func seedIfNeeded() {
        if files.isEmpty { files = spec.files }
        if activeFile.isEmpty { activeFile = spec.fileOrder.first ?? "" }
        if renderedDocument.isEmpty { run() }
    }

    private func run() {
        renderedDocument = spec.composedDocument(overriding: workingFiles)
    }

    private func reset() {
        files = spec.files
        run()
    }
}

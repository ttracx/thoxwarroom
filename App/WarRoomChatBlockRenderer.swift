// WarRoomChatBlockRenderer.swift
// SwiftUI renderers for each `ThoxBlock` case, mirroring the F1–F6 sections of
// the golden reference. Every renderer is pure — no network, no persistence.
// Sandpack and Artifact live in `WarRoomChatArtifactPanel.swift` because they
// carry a WKWebView.

import Charts
import SwiftUI

/// The dispatch view. Chooses the right renderer per block case.
struct ChatBlockView: View {
    let block: ThoxBlock
    /// Callback invoked when an artifact card is tapped. The chat surface
    /// owns the panel state so the panel can slide in from the leading edge
    /// (macOS) or full-screen sheet (iOS) without each block having its own
    /// presentation context.
    let onOpenArtifact: (ArtifactSpec) -> Void

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        switch block {
        case .markdown(let text):
            MarkdownBlockView(text: text)
        case .code(let language, let source):
            CodeBlockView(language: language, source: source)
        case .pendingCode(let language, let partial):
            PendingCodeBlockView(language: language, partial: partial)
        case .chart(let spec):
            ChartBlockView(spec: spec)
        case .mermaid(let source):
            MermaidBlockView(source: source)
        case .artifact(let spec):
            ArtifactCardView(spec: spec, onOpen: { onOpenArtifact(spec) })
        case .sandpack(let spec):
            SandpackBlockView(spec: spec)
        case .digitalHuman(let spec):
            DigitalHumanBlockView(spec: spec)
        }
    }
}

// MARK: - Markdown

/// Prose. Block structure (lists, headings, quotes) is segmented by
/// `ThoxMarkdownDocument`; each leaf string is rendered with the inline-only
/// AttributedString parser. See `ThoxMarkdownBody` in
/// `WarRoomChatRichRenderers.swift`.
struct MarkdownBlockView: View {
    let text: String

    var body: some View {
        ThoxMarkdownBody(text: text)
            .accessibilityIdentifier("chat-block-markdown")
    }
}

// MARK: - Code

/// Finished, language-tagged code. Highlighting comes from the lossless
/// `ThoxSyntaxHighlighter` tokenizer — see `ThoxHighlightedCodeBody` in
/// `WarRoomChatRichRenderers.swift`.
struct CodeBlockView: View {
    let language: String
    let source: String

    var body: some View {
        ThoxHighlightedCodeBody(language: language, source: source)
            .accessibilityIdentifier("chat-block-code")
            .accessibilityLabel("\(language) code block")
    }
}

private struct CopyButton: View {
    let text: String
    @State private var didCopy = false

    var body: some View {
        Button {
            copy(text)
            didCopy = true
            Task {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                didCopy = false
            }
        } label: {
            Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(didCopy ? ThoxTheme.accent : ThoxTheme.secondaryText)
        .accessibilityIdentifier("chat-block-copy")
    }

    private func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
    }
}

// MARK: - Pending code (streaming, not yet finished)

/// Distinct from `CodeBlockView` on purpose: no copy affordance and a
/// "receiving…" label so a half-arrived fence cannot be mistaken for a
/// finished block that is safe to act on.
struct PendingCodeBlockView: View {
    let language: String
    let partial: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(language.isEmpty ? "CODE" : language.uppercased())
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(ThoxTheme.secondaryText)
                Text("receiving…")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ThoxTheme.accent.opacity(0.18), in: Capsule())
                    .foregroundStyle(ThoxTheme.accent)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(partial.isEmpty ? " " : partial)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(ThoxTheme.primaryText)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .frame(minWidth: 0, alignment: .leading)
            }
        }
        .background(ThoxTheme.codeBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(ThoxTheme.accent.opacity(0.35))
        }
        .accessibilityIdentifier("chat-block-pending-code")
        .accessibilityLabel("Streaming \(language.isEmpty ? "code" : language) block, still receiving.")
    }

}

// MARK: - Chart

struct ChartBlockView: View {
    let spec: ChartSpec

    private var samples: [ChartSample] {
        zip(spec.labels, spec.values).enumerated().map { index, pair in
            ChartSample(id: index, label: pair.0, value: pair.1)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(spec.title)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(ThoxTheme.secondaryText)
                .textCase(.uppercase)
            Chart(samples) { sample in
                switch spec.kind {
                case .line:
                    LineMark(
                        x: .value("Label", sample.label),
                        y: .value("Value", sample.value)
                    )
                    .foregroundStyle(ThoxTheme.accent)
                    .interpolationMethod(.catmullRom)
                    AreaMark(
                        x: .value("Label", sample.label),
                        y: .value("Value", sample.value)
                    )
                    .foregroundStyle(ThoxTheme.accent.opacity(0.18))
                    .interpolationMethod(.catmullRom)
                case .bar:
                    BarMark(
                        x: .value("Label", sample.label),
                        y: .value("Value", sample.value)
                    )
                    .foregroundStyle(ThoxTheme.accent)
                }
            }
            .frame(height: 200)
            .chartXAxis {
                AxisMarks(preset: .aligned, values: .automatic) { _ in
                    AxisTick().foregroundStyle(ThoxTheme.separator)
                    AxisValueLabel().foregroundStyle(ThoxTheme.secondaryText)
                }
            }
            .chartYAxis {
                AxisMarks(preset: .aligned, values: .automatic) { _ in
                    AxisGridLine().foregroundStyle(ThoxTheme.separator)
                    AxisValueLabel().foregroundStyle(ThoxTheme.secondaryText)
                }
            }
        }
        .padding(12)
        .background(ThoxTheme.codeBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(ThoxTheme.separator) }
        .accessibilityIdentifier("chat-block-chart")
        .accessibilityLabel("Chart: \(spec.title)")
    }

}

private struct ChartSample: Identifiable {
    let id: Int
    let label: String
    let value: Double
}

// MARK: - Mermaid

/// Diagram. Rendered natively when the source is inside the supported Mermaid
/// flowchart subset, and as a labelled source pane when it is not — see
/// `ThoxMermaidBody` in `WarRoomChatRichRenderers.swift`.
struct MermaidBlockView: View {
    let source: String

    var body: some View {
        ThoxMermaidBody(source: source)
            .accessibilityIdentifier("chat-block-mermaid")
    }
}

// MARK: - Artifact card

struct ArtifactCardView: View {
    let spec: ArtifactSpec
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(ThoxTheme.codeBackground)
                    Text("</>")
                        .font(.system(.callout, design: .monospaced).weight(.bold))
                        .foregroundStyle(ThoxTheme.accent)
                }
                .frame(width: 34, height: 34)
                .overlay { RoundedRectangle(cornerRadius: 9).stroke(ThoxTheme.separator) }

                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(ThoxTheme.primaryText)
                    Text("artifact · \(spec.kind) · tap to open panel")
                        .font(.caption)
                        .foregroundStyle(ThoxTheme.secondaryText)
                }

                Spacer(minLength: 0)

                Text("Open ▸")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(ThoxTheme.accent)
            }
            .padding(12)
            .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(ThoxTheme.separator) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chat-block-artifact")
        .accessibilityLabel("Open artifact \(spec.title)")
    }

}

// MARK: - Sandpack

/// Editable live-code surface (F5). The editor and its bounded preview live in
/// `ThoxSandpackBody` in `WarRoomChatRichRenderers.swift`; the preview renders a
/// document composed entirely on-device through the same non-persistent,
/// navigation-cancelling web view the artifact panel uses.
struct SandpackBlockView: View {
    let spec: SandpackSpec

    var body: some View {
        ThoxSandpackBody(spec: spec)
            .accessibilityIdentifier("chat-block-sandpack")
    }
}

// MARK: - Digital Human turn

struct DigitalHumanBlockView: View {
    let spec: DigitalHumanSpec

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                statusDot
                Text(spec.persona)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(ThoxTheme.primaryText)
                Text(statusLabel)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(statusBackground, in: Capsule())
                    .foregroundStyle(ThoxTheme.background)
            }
            InlineMarkdownText(spec.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(digitalHumanBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 10).stroke(ThoxTheme.borderStrong, lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(statusBackground)
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Digital human \(spec.persona), \(statusLabel). \(spec.text)")
        .accessibilityIdentifier("chat-block-digital-human")
    }

    private var statusLabel: String {
        switch spec.status {
        case .running: return "running"
        case .awaitingApproval: return "awaiting approval"
        case .complete: return "complete"
        }
    }

    /// Amber while work is in flight, emerald when the turn is parked at an
    /// approval boundary, muted when it is done. Colour is the fastest read of
    /// "is something happening without me".
    private var statusBackground: Color {
        switch spec.status {
        case .running: return ThoxTheme.warning
        case .awaitingApproval: return ThoxTheme.accentLight
        case .complete: return ThoxTheme.secondaryText
        }
    }

    /// The golden reference pulses this dot while a turn is running. Motion is
    /// suppressed under Reduce Motion, where the static dot and the status pill
    /// already carry the same information.
    private var statusDot: some View {
        Circle()
            .fill(statusBackground)
            .frame(width: 8, height: 8)
            .overlay {
                Circle()
                    .stroke(statusBackground.opacity(pulsing ? 0 : 0.55), lineWidth: 4)
                    .scaleEffect(pulsing ? 2.2 : 1)
            }
            .onAppear {
                guard !reduceMotion, spec.status == .running else { return }
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
            }
            .accessibilityHidden(true)
    }

    private var digitalHumanBackground: some View {
        LinearGradient(
            colors: [
                ThoxTheme.accent.opacity(0.10),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

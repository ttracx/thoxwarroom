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
        switch block {
        case .markdown(let text):
            MarkdownBlockView(text: text)
        case .code(let language, let source):
            CodeBlockView(language: language, source: source)
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

struct MarkdownBlockView: View {
    let text: String

    var body: some View {
        Text(attributed)
            .font(.system(.body, design: .default))
            .foregroundStyle(ThoxTheme.primaryText)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("chat-block-markdown")
    }

    private var attributed: AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString(text)
    }
}

// MARK: - Code

struct CodeBlockView: View {
    let language: String
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(language.uppercased())
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(ThoxTheme.secondaryText)
                Spacer()
                CopyButton(text: source)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(source)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(ThoxTheme.primaryText)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .frame(minWidth: 0, alignment: .leading)
            }
        }
        .background(codeBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(ThoxTheme.separator) }
        .accessibilityIdentifier("chat-block-code")
        .accessibilityLabel("\(language) code block")
    }

    private var codeBackground: Color { Color(red: 13.0 / 255, green: 17.0 / 255, blue: 23.0 / 255) }
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
        .background(chartBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(ThoxTheme.separator) }
        .accessibilityIdentifier("chat-block-chart")
        .accessibilityLabel("Chart: \(spec.title)")
    }

    private var chartBackground: Color { Color(red: 13.0 / 255, green: 17.0 / 255, blue: 23.0 / 255) }
}

private struct ChartSample: Identifiable {
    let id: Int
    let label: String
    let value: Double
}

// MARK: - Mermaid

/// Native fallback: shows the mermaid source in a monospaced pane. Shipping a
/// full mermaid runtime would require a JavaScript execution surface we do not
/// yet want in the audit boundary. The pane is labeled so the user knows this
/// is a diagram source, not a code block.
struct MermaidBlockView: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Diagram · mermaid source", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(ThoxTheme.secondaryText)
                .textCase(.uppercase)
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
        .background(diagramBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(ThoxTheme.separator) }
        .accessibilityIdentifier("chat-block-mermaid")
        .accessibilityLabel("Mermaid diagram source")
    }

    private var diagramBackground: Color { Color(red: 13.0 / 255, green: 17.0 / 255, blue: 23.0 / 255) }
}

// MARK: - Artifact card

struct ArtifactCardView: View {
    let spec: ArtifactSpec
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(cardGlyphFill)
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

    private var cardGlyphFill: Color { Color(red: 13.0 / 255, green: 17.0 / 255, blue: 23.0 / 255) }
}

// MARK: - Sandpack

/// Read-only Sandpack surface. Displays the declared file tabs and shows the
/// source of the active tab. A live editable runtime waits on WR-004 evidence
/// review — the golden reference itself is labeled a "visual and interaction
/// fixture, not a production runtime."
struct SandpackBlockView: View {
    let spec: SandpackSpec
    @State private var activeFile: String?

    private var resolvedActiveFile: String {
        activeFile ?? spec.fileOrder.first ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Label(spec.template, systemImage: "curlybraces")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(ThoxTheme.secondaryText)
                    .textCase(.uppercase)
                Spacer(minLength: 8)
                Text("read-only preview")
                    .font(.caption)
                    .foregroundStyle(ThoxTheme.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(ThoxTheme.separator)

            HStack(spacing: 0) {
                ForEach(spec.fileOrder, id: \.self) { file in
                    Button(file) { activeFile = file }
                        .buttonStyle(.plain)
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(file == resolvedActiveFile ? ThoxTheme.accent : ThoxTheme.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(file == resolvedActiveFile ? ThoxTheme.accent : .clear)
                                .frame(height: 2)
                        }
                        .accessibilityLabel(file)
                        .accessibilityAddTraits(file == resolvedActiveFile ? [.isSelected] : [])
                }
                Spacer(minLength: 0)
            }

            Divider().overlay(ThoxTheme.separator)

            ScrollView(.vertical, showsIndicators: true) {
                Text(spec.files[resolvedActiveFile] ?? "")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(ThoxTheme.primaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 240)
        }
        .background(sandpackBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(ThoxTheme.separator) }
        .accessibilityIdentifier("chat-block-sandpack")
    }

    private var sandpackBackground: Color { Color(red: 13.0 / 255, green: 17.0 / 255, blue: 23.0 / 255) }
}

// MARK: - Digital Human turn

struct DigitalHumanBlockView: View {
    let spec: DigitalHumanSpec

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
                    .foregroundStyle(Color.black)
            }
            Text(spec.text)
                .font(.callout)
                .foregroundStyle(ThoxTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(digitalHumanBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 10).stroke(ThoxTheme.separator)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ThoxTheme.accent)
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

    private var statusBackground: Color {
        switch spec.status {
        case .running: return Color(red: 0.96, green: 0.70, blue: 0.00)
        case .awaitingApproval: return Color(red: 0.04, green: 0.82, blue: 0.42)
        case .complete: return Color.white.opacity(0.85)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusBackground)
            .frame(width: 7, height: 7)
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

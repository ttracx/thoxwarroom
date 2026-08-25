// WarRoomChatStreamParser.swift
// Pure, SwiftUI-free incremental parser that turns a partially received
// assistant token stream into the typed `ThoxBlock` presentation contract.
//
// Why a dedicated parser instead of a Markdown library:
//
// 1. The stream is *partial by construction*. A general Markdown parser sees an
//    unterminated ``` fence as prose and re-classifies it as code one token
//    later, which makes the transcript flicker between two very different
//    layouts on every delta. This parser models "still receiving a fence" as an
//    explicit `.pendingCode` state that never re-classifies.
// 2. Reasoning (`<think>`) must be split *before* block segmentation, and an
//    unterminated `<think>` must not leak into the visible answer.
// 3. The typed directive fences (`thoxchart`, `thoxartifact`, `thoxsandpack`,
//    `thoxagent`) are only promoted to rich blocks once their closing fence has
//    arrived and their JSON payload validates, so a half-received chart can
//    never render as a broken card.
//
// The parser is deliberately total: every input produces a well-formed result,
// and no input path throws. Malformed directive payloads degrade to a plain
// code block rather than being dropped, so a model that emits bad JSON still
// shows the user what it actually said.

import Foundation

/// The result of parsing one assistant message body at a point in time.
struct ParsedAssistantMessage: Equatable {
    /// Contents of a `<think>` section, if one was opened.
    let reasoning: String?

    /// True while a `<think>` block has been opened but not yet closed. The
    /// view uses this to label the disclosure "Thinking…" instead of
    /// "Reasoning".
    let isReasoningOpen: Bool

    /// Visible answer blocks, in stream order.
    let blocks: [ThoxBlock]

    static let empty = ParsedAssistantMessage(reasoning: nil, isReasoningOpen: false, blocks: [])

    /// True when there is nothing at all to render yet.
    var isEmpty: Bool { reasoning == nil && blocks.isEmpty }
}

/// Stateless incremental parser. Call `parse(_:)` with the full accumulated
/// text after every delta; it is O(n) in the message length and messages are
/// bounded by the transport's `maxTokens`.
enum WarRoomChatStreamParser {

    private static let thinkOpen = "<think>"
    private static let thinkClose = "</think>"
    private static let fence = "```"

    /// Parse an accumulated assistant message body.
    static func parse(_ raw: String) -> ParsedAssistantMessage {
        let split = splitReasoning(raw)
        let blocks = segment(split.body)
        return ParsedAssistantMessage(
            reasoning: split.reasoning,
            isReasoningOpen: split.isOpen,
            blocks: blocks
        )
    }

    // MARK: - Reasoning

    struct ReasoningSplit: Equatable {
        let reasoning: String?
        let isOpen: Bool
        let body: String
    }

    /// Split a leading `<think>…</think>` section off the message body.
    ///
    /// Three cases matter:
    /// - no open tag: everything is body;
    /// - open tag with a matching close: reasoning is between them, body is
    ///   what follows;
    /// - open tag with no close yet: everything after the tag is reasoning and
    ///   the body is empty, so a partial chain of thought never renders as the
    ///   answer.
    static func splitReasoning(_ raw: String) -> ReasoningSplit {
        guard let openRange = raw.range(of: thinkOpen) else {
            return ReasoningSplit(reasoning: nil, isOpen: false, body: raw)
        }

        let leading = String(raw[raw.startIndex..<openRange.lowerBound])
        let afterOpen = raw[openRange.upperBound...]

        guard let closeRange = afterOpen.range(of: thinkClose) else {
            let reasoning = String(afterOpen).trimmingCharacters(in: .whitespacesAndNewlines)
            return ReasoningSplit(
                reasoning: reasoning.isEmpty ? nil : reasoning,
                isOpen: true,
                body: leading
            )
        }

        let reasoning = String(afterOpen[afterOpen.startIndex..<closeRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trailing = String(afterOpen[closeRange.upperBound...])
        let body = (leading + trailing)

        return ReasoningSplit(
            reasoning: reasoning.isEmpty ? nil : reasoning,
            isOpen: false,
            body: body
        )
    }

    // MARK: - Block segmentation

    /// Line-oriented fence scanner. A fence only becomes a finished block when
    /// its closing fence arrives; until then it is `.pendingCode`.
    static func segment(_ body: String) -> [ThoxBlock] {
        guard !body.isEmpty else { return [] }

        var blocks: [ThoxBlock] = []
        var prose: [String] = []
        var fenceLanguage: String?
        var fenceLines: [String] = []
        var insideFence = false

        func flushProse() {
            let text = prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            prose.removeAll(keepingCapacity: true)
            guard !text.isEmpty else { return }
            blocks.append(.markdown(text))
        }

        // `omittingEmptySubsequences: false` keeps blank lines, which matter
        // for Markdown paragraph breaks and for code fidelity.
        for line in body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix(fence) {
                if insideFence {
                    // Closing fence: the block is now complete and safe to promote.
                    blocks.append(
                        finishedBlock(
                            language: fenceLanguage ?? "",
                            source: fenceLines.joined(separator: "\n")
                        )
                    )
                    fenceLanguage = nil
                    fenceLines.removeAll(keepingCapacity: true)
                    insideFence = false
                } else {
                    flushProse()
                    let info = String(trimmed.dropFirst(fence.count))
                        .trimmingCharacters(in: .whitespaces)
                    fenceLanguage = info
                    insideFence = true
                }
                continue
            }

            if insideFence {
                fenceLines.append(line)
            } else {
                prose.append(line)
            }
        }

        if insideFence {
            // Unterminated fence — surface it as explicitly in-flight rather
            // than guessing that the model meant to close it.
            blocks.append(
                .pendingCode(
                    language: normalizedLanguage(fenceLanguage ?? ""),
                    partial: fenceLines.joined(separator: "\n")
                )
            )
        } else {
            flushProse()
        }

        return blocks
    }

    // MARK: - Directive promotion

    /// Promote a completed fence to its typed block, falling back to a plain
    /// code block whenever the payload does not validate.
    private static func finishedBlock(language rawLanguage: String, source: String) -> ThoxBlock {
        let language = normalizedLanguage(rawLanguage)

        switch language {
        case "mermaid":
            return .mermaid(source: source)

        case "thoxchart":
            if let spec = decodeChart(source) { return .chart(spec) }

        case "thoxartifact":
            if let spec = decodeArtifact(source) { return .artifact(spec) }

        case "thoxsandpack":
            if let spec = decodeSandpack(source) { return .sandpack(spec) }

        case "thoxagent":
            if let spec = decodeDigitalHuman(source) { return .digitalHuman(spec) }

        default:
            break
        }

        return .code(language: language.isEmpty ? "text" : language, source: source)
    }

    /// Fence info strings can carry attributes (```` ```swift title=x ````);
    /// only the first token is the language.
    static func normalizedLanguage(_ raw: String) -> String {
        raw.split(separator: " ").first.map { $0.lowercased() } ?? ""
    }

    // MARK: - Payload decoding
    //
    // Each decoder is fail-soft on purpose: `nil` means "render the raw source
    // as code", which is always truthful about what the model produced.

    private static func json(_ source: String) -> [String: Any]? {
        guard let data = source.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func decodeChart(_ source: String) -> ChartSpec? {
        guard let object = json(source) else { return nil }
        let labels = (object["labels"] as? [Any])?.compactMap { value -> String? in
            if let string = value as? String { return string }
            if let number = value as? NSNumber { return number.stringValue }
            return nil
        } ?? []
        let values = (object["values"] as? [Any])?.compactMap { ($0 as? NSNumber)?.doubleValue } ?? []
        guard !labels.isEmpty, labels.count == values.count else { return nil }

        let kind = ChartSpec.Kind(rawValue: (object["kind"] as? String)?.lowercased() ?? "line") ?? .line
        return ChartSpec(
            kind: kind,
            title: (object["title"] as? String) ?? "Chart",
            labels: labels,
            values: values
        )
    }

    static func decodeArtifact(_ source: String) -> ArtifactSpec? {
        guard let object = json(source),
              let html = object["source"] as? String, !html.isEmpty else { return nil }
        return ArtifactSpec(
            artifactID: (object["id"] as? String) ?? UUID().uuidString,
            title: (object["title"] as? String) ?? "Artifact",
            kind: (object["kind"] as? String) ?? "html",
            source: html
        )
    }

    static func decodeSandpack(_ source: String) -> SandpackSpec? {
        guard let object = json(source),
              let files = object["files"] as? [String: String], !files.isEmpty else { return nil }
        // Preserve the model's declared order when given, else sort for
        // deterministic rendering and tests.
        let declared = (object["fileOrder"] as? [String])?.filter { files[$0] != nil } ?? []
        let order = declared.isEmpty ? files.keys.sorted() : declared
        return SandpackSpec(
            template: (object["template"] as? String) ?? "vanilla",
            fileOrder: order,
            files: files
        )
    }

    static func decodeDigitalHuman(_ source: String) -> DigitalHumanSpec? {
        guard let object = json(source),
              let persona = object["persona"] as? String, !persona.isEmpty,
              let text = object["text"] as? String else { return nil }
        let status = DigitalHumanSpec.Status(
            rawValue: (object["status"] as? String) ?? "running"
        ) ?? .running
        return DigitalHumanSpec(persona: persona, status: status, text: text)
    }
}

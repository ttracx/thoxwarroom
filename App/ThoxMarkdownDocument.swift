// ThoxMarkdownDocument.swift
// Block-level Markdown segmentation for the ThoxOS chat surface.
//
// WHY THIS EXISTS
// ---------------
// `AttributedString(markdown:)` with `.inlineOnlyPreservingWhitespace` is the
// only Markdown mode we can safely use for a streamed assistant turn: the full
// parser will happily swallow an unterminated fence and restructure the whole
// message. But inline-only mode also means a bullet list renders as the literal
// characters `- item`, which is a visible regression against both the golden
// reference (`chat-ux-golden.html`, which renders a real `<ul>`) and the
// ThoxMythos product surface (`.thox-prose ul { list-style: disc }`).
//
// The fix is to split block structure ourselves — deterministically, with no
// network and no HTML — and then hand each *leaf* string to the inline-only
// AttributedString parser. Fenced code never reaches here: fences are their own
// `ThoxBlock.code` case, which is what keeps a partially streamed code segment
// from desynchronizing a second parser.
//
// This file is intentionally Foundation-only so it is unit-testable on every
// platform and cannot acquire a UI or transport dependency by accident.

import Foundation

/// A Markdown paragraph stream reduced to the small set of block shapes the
/// chat surface renders natively.
struct ThoxMarkdownDocument: Equatable {
    /// One block-level node.
    enum Node: Equatable {
        /// `# ` … `###### ` — level is clamped to 1...6.
        case heading(level: Int, text: String)
        /// A run of non-blank lines that is not any other shape.
        case paragraph(String)
        /// `- `, `* `, or `+ ` items, in source order.
        case unorderedList(items: [String])
        /// `1. ` items. `start` is the first marker's integer value.
        case orderedList(start: Int, items: [String])
        /// `> ` quoted lines, joined into paragraphs.
        case blockQuote(paragraphs: [String])
        /// `---`, `***`, or `___` on its own line.
        case thematicBreak
    }

    /// Nodes in source order. Empty for empty or whitespace-only input.
    let nodes: [Node]

    /// True when the document is a single paragraph — the common case for a
    /// user turn or a Digital Human summary, where the caller can skip the
    /// per-node layout entirely.
    var isSingleParagraph: Bool {
        guard nodes.count == 1, case .paragraph = nodes[0] else { return false }
        return true
    }

    // MARK: - Parsing

    /// Splits `source` into block nodes.
    ///
    /// The parser is single-pass and total: every input produces a document, and
    /// anything it does not recognize degrades to a paragraph containing the
    /// original text. It never throws and never drops characters that carry
    /// meaning.
    static func parse(_ source: String) -> ThoxMarkdownDocument {
        var nodes: [Node] = []
        // `omittingEmptySubsequences: false` keeps blank lines, which are the
        // only block separator Markdown gives us.
        let lines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var index = 0
        while index < lines.count {
            let raw = lines[index]
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                index += 1
                continue
            }

            if isThematicBreak(line) {
                nodes.append(.thematicBreak)
                index += 1
                continue
            }

            if let heading = parseHeading(line) {
                nodes.append(heading)
                index += 1
                continue
            }

            if unorderedMarker(line) != nil {
                let (items, next) = collectUnordered(lines, from: index)
                nodes.append(.unorderedList(items: items))
                index = next
                continue
            }

            if let first = orderedMarker(line) {
                let (items, next) = collectOrdered(lines, from: index)
                nodes.append(.orderedList(start: first.number, items: items))
                index = next
                continue
            }

            if line.hasPrefix(">") {
                let (paragraphs, next) = collectQuote(lines, from: index)
                nodes.append(.blockQuote(paragraphs: paragraphs))
                index = next
                continue
            }

            let (paragraph, next) = collectParagraph(lines, from: index)
            if !paragraph.isEmpty {
                nodes.append(.paragraph(paragraph))
            }
            index = next
        }

        return ThoxMarkdownDocument(nodes: nodes)
    }

    // MARK: - Line classification

    private static func isThematicBreak(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3 else { return false }
        return compact.allSatisfy { $0 == "-" } ||
            compact.allSatisfy { $0 == "*" } ||
            compact.allSatisfy { $0 == "_" }
    }

    private static func parseHeading(_ line: String) -> Node? {
        var level = 0
        var remainder = Substring(line)
        while remainder.first == "#" && level < 6 {
            level += 1
            remainder = remainder.dropFirst()
        }
        guard level > 0 else { return nil }
        // ATX headings require whitespace after the run of `#`; `#hashtag` is
        // prose, not a heading.
        guard remainder.first == " " || remainder.isEmpty else { return nil }
        let text = remainder.trimmingCharacters(in: .whitespaces)
        return .heading(level: level, text: text)
    }

    /// Returns the content following an unordered list marker, or `nil`.
    private static func unorderedMarker(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        // A bare marker on its own line is an empty item, not prose.
        if line == "-" || line == "*" || line == "+" { return "" }
        return nil
    }

    /// Returns the parsed number and content following an ordered list marker.
    private static func orderedMarker(_ line: String) -> (number: Int, content: String)? {
        var digits = ""
        var remainder = Substring(line)
        while let first = remainder.first, first.isNumber, digits.count < 9 {
            digits.append(first)
            remainder = remainder.dropFirst()
        }
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        guard remainder.first == "." || remainder.first == ")" else { return nil }
        remainder = remainder.dropFirst()
        guard remainder.first == " " || remainder.isEmpty else { return nil }
        return (number, remainder.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Block collection

    private static func collectUnordered(_ lines: [String], from start: Int) -> ([String], Int) {
        var items: [String] = []
        var index = start
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if let content = unorderedMarker(line) {
                items.append(content)
                index += 1
                continue
            }
            // An indented, non-marker, non-blank line continues the last item.
            if !line.isEmpty, !items.isEmpty, lines[index].hasPrefix(" ") {
                items[items.count - 1] = joined(items[items.count - 1], line)
                index += 1
                continue
            }
            break
        }
        return (items, index)
    }

    private static func collectOrdered(_ lines: [String], from start: Int) -> ([String], Int) {
        var items: [String] = []
        var index = start
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if let marker = orderedMarker(line) {
                items.append(marker.content)
                index += 1
                continue
            }
            if !line.isEmpty, !items.isEmpty, lines[index].hasPrefix(" ") {
                items[items.count - 1] = joined(items[items.count - 1], line)
                index += 1
                continue
            }
            break
        }
        return (items, index)
    }

    private static func collectQuote(_ lines: [String], from start: Int) -> ([String], Int) {
        var paragraphs: [String] = []
        var current = ""
        var index = start
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix(">") else { break }
            var content = Substring(line.dropFirst())
            if content.first == " " { content = content.dropFirst() }
            let text = String(content)
            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty {
                    paragraphs.append(current)
                    current = ""
                }
            } else {
                current = joined(current, text)
            }
            index += 1
        }
        if !current.isEmpty { paragraphs.append(current) }
        return (paragraphs, index)
    }

    private static func collectParagraph(_ lines: [String], from start: Int) -> (String, Int) {
        var text = ""
        var index = start
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { break }
            // Stop before a line that starts a different block shape, so
            // `paragraph` immediately followed by `- item` does not absorb it.
            if index > start {
                if isThematicBreak(line) { break }
                if parseHeading(line) != nil { break }
                if unorderedMarker(line) != nil { break }
                if orderedMarker(line) != nil { break }
                if line.hasPrefix(">") { break }
            }
            text = joined(text, line)
            index += 1
        }
        return (text, index)
    }

    /// Joins a soft-wrapped continuation line the way Markdown does: a single
    /// space, never a newline.
    private static func joined(_ existing: String, _ addition: String) -> String {
        existing.isEmpty ? addition : existing + " " + addition
    }
}

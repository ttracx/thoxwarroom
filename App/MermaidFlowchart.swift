// MermaidFlowchart.swift
// A bounded, dependency-free parser for the subset of Mermaid flowchart syntax
// the ThoxOS chat surface renders natively.
//
// WHY THIS EXISTS
// ---------------
// The golden reference renders `graph LR; U[User]-->C[ThoxOS Chat]; …` with
// mermaid.js. The native surface cannot: mermaid is a JavaScript runtime, and
// putting a script-executing web view inline in the transcript is exactly what
// the audit boundary excludes. The previous native fallback printed the raw
// source in a monospaced pane, which is honest but is a real UX regression —
// the reader has to parse a graph in their head.
//
// This parser covers the flowchart shapes THOX actually emits. Anything it does
// not understand returns `nil`, and the view falls back to the labelled source
// pane. That degradation is deliberate: a half-drawn diagram is worse than a
// clearly-labelled block of source.
//
// Foundation-only and total. No regex, no locale, no recursion.

import Foundation

/// A parsed Mermaid flowchart: nodes, directed edges, and a layered layout.
struct MermaidFlowchart: Equatable {
    /// Layout axis declared by `graph LR` / `flowchart TD` etc.
    enum Direction: String, Equatable {
        case leftRight = "LR"
        case rightLeft = "RL"
        case topDown = "TD"
        case topBottom = "TB"
        case bottomTop = "BT"

        /// True when ranks advance horizontally.
        var isHorizontal: Bool { self == .leftRight || self == .rightLeft }
    }

    /// Node outline, taken from the bracket style in the source.
    enum Shape: Equatable {
        case rectangle
        case rounded
        case stadium
        case diamond
        case circle
    }

    /// Line style for a connector.
    enum EdgeStyle: Equatable {
        case solid
        case dotted
        case thick
    }

    struct Node: Equatable, Identifiable {
        let id: String
        let label: String
        let shape: Shape
    }

    struct Edge: Equatable {
        let from: String
        let to: String
        let label: String?
        let style: EdgeStyle
        /// False for `---` style connectors, which draw no arrowhead.
        let isDirected: Bool
    }

    let direction: Direction
    /// Nodes in first-appearance order.
    let nodes: [Node]
    let edges: [Edge]

    // MARK: - Limits

    /// Above these sizes the native diagram stops being readable in a chat
    /// bubble, so the caller falls back to the source pane instead.
    static let maximumNodes = 48
    static let maximumEdges = 96
    static let maximumSourceLength = 8_000

    // MARK: - Layout

    /// Nodes grouped into layout ranks by longest path from a root.
    ///
    /// Cycles are tolerated: relaxation runs at most `nodes.count` passes, so a
    /// cyclic graph settles into a stable — if arbitrary — layering rather than
    /// looping forever.
    var ranks: [[Node]] {
        guard !nodes.isEmpty else { return [] }
        var level: [String: Int] = [:]
        for node in nodes { level[node.id] = 0 }

        let forwardEdges = edges.filter { $0.from != $0.to }
        var passes = 0
        var changed = true
        while changed && passes < nodes.count {
            changed = false
            passes += 1
            for edge in forwardEdges {
                let candidate = (level[edge.from] ?? 0) + 1
                if candidate > (level[edge.to] ?? 0) {
                    level[edge.to] = candidate
                    changed = true
                }
            }
        }

        let depth = (level.values.max() ?? 0) + 1
        var buckets: [[Node]] = Array(repeating: [], count: depth)
        for node in nodes {
            buckets[min(level[node.id] ?? 0, depth - 1)].append(node)
        }
        return buckets.filter { !$0.isEmpty }
    }

    /// Looks up a node by identifier. Linear, but `nodes` is capped at 48.
    func node(id: String) -> Node? {
        nodes.first { $0.id == id }
    }

    // MARK: - Parsing

    /// Parses a Mermaid flowchart, or returns `nil` when the source uses syntax
    /// this renderer does not model.
    static func parse(_ source: String) -> MermaidFlowchart? {
        guard !source.isEmpty, source.count <= maximumSourceLength else { return nil }

        var direction = Direction.leftRight
        var orderedNodes: [Node] = []
        var nodeIndex: [String: Int] = [:]
        var edges: [Edge] = []
        var sawHeader = false

        func register(_ node: Node) {
            if let existing = nodeIndex[node.id] {
                // A later mention carrying a label wins over a bare reference.
                if orderedNodes[existing].label == orderedNodes[existing].id,
                   node.label != node.id {
                    orderedNodes[existing] = node
                }
                return
            }
            nodeIndex[node.id] = orderedNodes.count
            orderedNodes.append(node)
        }

        for rawStatement in statements(in: source) {
            let statement = rawStatement.trimmingCharacters(in: .whitespaces)
            if statement.isEmpty { continue }

            if !sawHeader, let declared = parseHeader(statement) {
                direction = declared.direction
                sawHeader = true
                if declared.remainder.isEmpty { continue }
                guard let chain = parseChain(declared.remainder) else { return nil }
                chain.nodes.forEach(register)
                edges.append(contentsOf: chain.edges)
                continue
            }

            // Directives we deliberately do not model.
            for unsupported in ["subgraph", "end", "click", "style", "classDef", "class ", "linkStyle"]
            where statement.hasPrefix(unsupported) {
                return nil
            }

            guard let chain = parseChain(statement) else { return nil }
            chain.nodes.forEach(register)
            edges.append(contentsOf: chain.edges)
        }

        guard sawHeader || !edges.isEmpty else { return nil }
        guard !orderedNodes.isEmpty else { return nil }
        guard orderedNodes.count <= maximumNodes, edges.count <= maximumEdges else { return nil }

        return MermaidFlowchart(direction: direction, nodes: orderedNodes, edges: edges)
    }

    /// Splits source into statements on `;` and newlines, dropping `%%` comments.
    private static func statements(in source: String) -> [String] {
        source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(whereSeparator: { $0 == ";" || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("%%") }
    }

    /// Consumes a leading `graph LR` / `flowchart TD` header.
    private static func parseHeader(_ statement: String) -> (direction: Direction, remainder: String)? {
        for keyword in ["flowchart", "graph"] where statement.hasPrefix(keyword) {
            var rest = Substring(statement.dropFirst(keyword.count))
            guard rest.first == nil || rest.first!.isWhitespace else { return nil }
            rest = Substring(rest.drop(while: { $0.isWhitespace }))
            let token = String(rest.prefix(while: { !$0.isWhitespace }))
            guard let direction = Direction(rawValue: token.uppercased()) else {
                // `graph` with no direction is legal Mermaid and defaults to TB.
                return (.topBottom, String(rest).trimmingCharacters(in: .whitespaces))
            }
            let remainder = String(rest.dropFirst(token.count)).trimmingCharacters(in: .whitespaces)
            return (direction, remainder)
        }
        return nil
    }

    /// Characters that can appear inside a connector run.
    ///
    /// Mermaid's circle (`--o`) and cross (`--x`) arrowheads are deliberately
    /// excluded: `o` and `x` are also legal first characters of a node id, and
    /// admitting them would swallow `R-->ox` as a connector. Sources using them
    /// fail the chain arity check and fall back to the labelled source pane.
    private static let connectorCharacters: Set<Character> = ["-", "=", ".", ">", "<"]

    /// Parses `A[Label] --> B{Label} -.-> C` into nodes and edges.
    private static func parseChain(_ statement: String) -> (nodes: [Node], edges: [Edge])? {
        let characters = Array(statement)
        var index = 0
        var nodes: [Node] = []
        var connectors: [(label: String?, style: EdgeStyle, isDirected: Bool)] = []

        while index < characters.count {
            while index < characters.count, characters[index].isWhitespace { index += 1 }
            if index >= characters.count { break }

            guard let parsed = parseNode(characters, from: index) else { return nil }
            nodes.append(parsed.node)
            index = parsed.end

            while index < characters.count, characters[index].isWhitespace { index += 1 }
            if index >= characters.count { break }

            guard let connector = parseConnector(characters, from: index) else { return nil }
            connectors.append((connector.label, connector.style, connector.isDirected))
            index = connector.end
        }

        // A connector always sits between two nodes; a trailing connector with
        // no destination is malformed and falls back to the source pane.
        guard connectors.count == max(nodes.count - 1, 0) else { return nil }

        var edges: [Edge] = []
        for (offset, connector) in connectors.enumerated() {
            edges.append(
                Edge(
                    from: nodes[offset].id,
                    to: nodes[offset + 1].id,
                    label: connector.label,
                    style: connector.style,
                    isDirected: connector.isDirected
                )
            )
        }

        return (nodes, edges)
    }

    /// Parses one node reference, with or without a bracketed label.
    private static func parseNode(
        _ characters: [Character],
        from start: Int
    ) -> (node: Node, end: Int)? {
        var index = start
        var identifier = ""
        while index < characters.count {
            let character = characters[index]
            if character.isLetter || character.isNumber || character == "_" {
                identifier.append(character)
                index += 1
                continue
            }
            break
        }
        guard !identifier.isEmpty else { return nil }

        guard index < characters.count, let opener = Opener(characters[index]) else {
            return (Node(id: identifier, label: identifier, shape: .rectangle), index)
        }

        // Determine the shape from the opening run (`(`, `((`, `([`, `[`, `{`).
        var depth = 0
        var body = ""
        var cursor = index
        var quoted = false
        while cursor < characters.count {
            let character = characters[cursor]
            if character == "\"" { quoted.toggle() }
            if !quoted {
                if opener.opens.contains(character) { depth += 1 }
                if opener.closes.contains(character) {
                    depth -= 1
                    if depth == 0 {
                        cursor += 1
                        let label = normalizeLabel(body)
                        let shape = opener.shape(source: characters, start: index, end: cursor)
                        return (Node(id: identifier, label: label, shape: shape), cursor)
                    }
                }
            }
            if depth > 0, !opener.opens.contains(character) || depth > 1 {
                body.append(character)
            }
            cursor += 1
        }
        return nil
    }

    /// Bracket family for a node label.
    private struct Opener {
        let opens: Set<Character>
        let closes: Set<Character>
        private let base: Shape

        init?(_ character: Character) {
            switch character {
            case "[":
                opens = ["["]; closes = ["]"]; base = .rectangle
            case "(":
                opens = ["("]; closes = [")"]; base = .rounded
            case "{":
                opens = ["{"]; closes = ["}"]; base = .diamond
            default:
                return nil
            }
        }

        /// Refines the base shape using the exact opening run: `((x))` is a
        /// circle, `([x])` is a stadium.
        func shape(source: [Character], start: Int, end: Int) -> Shape {
            guard end - start >= 4, start + 1 < source.count else { return base }
            switch (source[start], source[start + 1]) {
            case ("(", "("):
                return .circle
            case ("(", "["):
                return .stadium
            default:
                return base
            }
        }
    }

    /// Strips Mermaid label quoting and collapses whitespace.
    private static func normalizeLabel(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespaces)
        // A stadium/circle body still carries its inner bracket characters.
        while let first = text.first, first == "[" || first == "(" || first == "\"" {
            text = String(text.dropFirst())
        }
        while let last = text.last, last == "]" || last == ")" || last == "\"" {
            text = String(text.dropLast())
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Parses a connector, including both `-->|label|` and `-- label -->` forms.
    private static func parseConnector(
        _ characters: [Character],
        from start: Int
    ) -> (label: String?, style: EdgeStyle, isDirected: Bool, end: Int)? {
        var index = start
        var run = ""
        while index < characters.count, connectorCharacters.contains(characters[index]) {
            run.append(characters[index])
            index += 1
        }
        guard run.count >= 2 else { return nil }

        var style = EdgeStyle.solid
        if run.contains(".") { style = .dotted }
        if run.contains("=") { style = .thick }
        var isDirected = run.contains(">") || run.contains("<")
        var label: String?

        // `-->|label|`
        if index < characters.count, characters[index] == "|" {
            var cursor = index + 1
            var text = ""
            while cursor < characters.count, characters[cursor] != "|" {
                text.append(characters[cursor])
                cursor += 1
            }
            guard cursor < characters.count else { return nil }
            label = normalizeLabel(text)
            index = cursor + 1
            return (label, style, isDirected, index)
        }

        // `-- label -->` : the first run had no arrowhead, so look for a second
        // run after an intervening label.
        if !isDirected {
            var cursor = index
            var text = ""
            while cursor < characters.count, !connectorCharacters.contains(characters[cursor]) {
                // A bracket means we already reached the next node, so the
                // connector was a plain undirected link after all.
                if characters[cursor] == "[" || characters[cursor] == "(" || characters[cursor] == "{" {
                    return (nil, style, false, index)
                }
                text.append(characters[cursor])
                cursor += 1
            }
            var secondRun = ""
            while cursor < characters.count, connectorCharacters.contains(characters[cursor]) {
                secondRun.append(characters[cursor])
                cursor += 1
            }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if secondRun.count >= 2, !trimmed.isEmpty {
                if secondRun.contains(".") { style = .dotted }
                if secondRun.contains("=") { style = .thick }
                isDirected = secondRun.contains(">")
                return (trimmed, style, isDirected, cursor)
            }
        }

        return (nil, style, isDirected, index)
    }
}

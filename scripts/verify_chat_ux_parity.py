#!/usr/bin/env python3
"""Verify the native ThoxOS chat surface against its golden reference.

WHY THIS EXISTS
---------------
The chat surface is Swift, and Swift can only be compiled on a macOS host with
Xcode. Every review pass that happens off that host — CI on a Linux runner, an
agent iterating on the surface, a reviewer reading a diff — currently has no way
to catch a fixture that drifted from `chat-ux-golden.html`, a `ThoxBlock` case
that lost its renderer, or a chat file that quietly acquired a network API.

This script closes that gap without a toolchain. It does four things:

  1. FIXTURE PARITY   Parses the `blocks[]` wire contract out of
                      `chat-ux-golden.html` and the `ChatFixture` literal out of
                      `WarRoomChatBlocks.swift`, then compares them
                      block-for-block.
  2. RENDERER COVERAGE Asserts every `ThoxBlock` case has a `case` arm in
                      `ChatBlockView`.
  3. BOUNDARY         Asserts no file on the chat path references a network API.
  4. ALGORITHM        Runs line-for-line Python ports of the three Foundation-only
                      parsers against the golden inputs, so their behaviour is
                      proven before anyone opens Xcode. The ports are a
                      cross-check, not a second implementation: if a port and its
                      Swift original disagree, that is the finding.

Exit codes: 0 all checks pass, 1 one or more findings, 2 a required input is
missing (which is itself a failure, not a skip).

Usage:  python3 scripts/verify_chat_ux_parity.py [--repo-root PATH] [--verbose]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

# The reviewed reference. A mismatch means someone replaced the fixture without
# re-reviewing it, which is exactly what this check is for.
GOLDEN_SHA256 = "86bdce5a7206ac2ce0b9191db4bf412508a3d5bb3c43aeb180fc267e33a674cd"

GOLDEN_HTML = Path("docs/fixtures/current-service-contracts/chat-ux-golden.html")

# Files that make up the chat presentation path.
CHAT_FILES = [
    "App/WarRoomChatBlocks.swift",
    "App/WarRoomChatBlockRenderer.swift",
    "App/WarRoomChatRichRenderers.swift",
    "App/WarRoomChatArtifactPanel.swift",
    "App/WarRoomChatPreviewView.swift",
    "App/WarRoomChatPreviewModel.swift",
    "App/WarRoomChatPreviewHost.swift",
    "App/ThoxMarkdownDocument.swift",
    "App/ThoxSyntaxHighlighter.swift",
    "App/MermaidFlowchart.swift",
]

# Pure parsing/model files that must never gain a UI or transport import.
PURE_FILES = [
    "App/ThoxMarkdownDocument.swift",
    "App/ThoxSyntaxHighlighter.swift",
    "App/MermaidFlowchart.swift",
]

# Network APIs that must not appear on the presentation path. The transport
# lives behind `ChatTransport`, in its own file, behind the WR-004 gate.
FORBIDDEN_ON_PRESENTATION_PATH = [
    "URLSession",
    "URLRequest",
    "NWConnection",
    "CFStream",
    "Network.framework",
]

# Canonical THOX palette. Drift here is how two THOX surfaces end up different
# shades of green, which is the exact bug this table was introduced to fix.
REQUIRED_TOKENS = {
    "accent": "0x10B981",
    "accentLight": "0x34D399",
    "accentDeep": "0x059669",
    "background": "0x09090B",
    "surface": "0x18181B",
    "borderStrong": "0x3F3F46",
    "primaryText": "0xFAFAFA",
    "secondaryText": "0xA1A1AA",
    "faintText": "0x71717A",
}


# --------------------------------------------------------------------------- #
# Result plumbing
# --------------------------------------------------------------------------- #


@dataclass
class Report:
    passed: list[str] = field(default_factory=list)
    findings: list[str] = field(default_factory=list)

    def ok(self, message: str) -> None:
        self.passed.append(message)

    def fail(self, message: str) -> None:
        self.findings.append(message)

    def check(self, condition: bool, message: str) -> bool:
        (self.ok if condition else self.fail)(message)
        return condition


# --------------------------------------------------------------------------- #
# 1. Fixture parity
# --------------------------------------------------------------------------- #


def golden_block_types(html: str) -> list[str]:
    """Extract the ordered `type:` discriminators from the reference `blocks[]`."""
    start = html.index("const blocks = [")
    end = html.index("\n];", start)
    body = html[start:end]
    return re.findall(r'\{\s*type\s*:\s*"([a-z_]+)"', body)


def swift_block_types(swift: str) -> list[str]:
    """Extract the ordered case names from `ChatFixture.goldenAssistantBlocks`."""
    start = swift.index("static let goldenAssistantBlocks")
    # The literal ends at the closing bracket that sits at four-space indent.
    end = swift.index("\n    ]", start)
    body = swift[start:end]
    # Only top-level (8-space indented) `.case(` entries are blocks; nested
    # payload members are indented deeper.
    return re.findall(r"^        \.([a-zA-Z]+)\(", body, flags=re.MULTILINE)


# The reference discriminator -> the Swift case that must render it.
BLOCK_TYPE_MAP = {
    "markdown": "markdown",
    "code": "code",
    "chart": "chart",
    "mermaid": "mermaid",
    "artifact": "artifact",
    "sandpack": "sandpack",
    "dh_turn": "digitalHuman",
}


def check_fixture_parity(root: Path, report: Report) -> None:
    html_path = root / GOLDEN_HTML
    swift_path = root / "App/WarRoomChatBlocks.swift"
    if not html_path.exists():
        report.fail(f"missing golden reference: {GOLDEN_HTML}")
        return
    if not swift_path.exists():
        report.fail("missing App/WarRoomChatBlocks.swift")
        return

    raw = html_path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    report.check(
        digest == GOLDEN_SHA256,
        f"golden reference sha256 matches the reviewed fixture ({digest[:12]}…)",
    )

    html = raw.decode("utf-8")
    swift = swift_path.read_text(encoding="utf-8")

    reference = golden_block_types(html)
    expected = [BLOCK_TYPE_MAP[t] for t in reference]
    actual = swift_block_types(swift)

    report.check(
        actual == expected,
        f"fixture block order matches the reference: {' → '.join(expected)}"
        if actual == expected
        else f"fixture block order drifted — reference {expected}, swift {actual}",
    )

    # Content spot-checks on the values a reader would notice immediately.
    checks = [
        ("Fleet tokens / hr", "chart title"),
        ("Counter dashboard", "artifact title"),
        ("Victoria", "digital human persona"),
        ("graph LR;", "mermaid source"),
        ("index.html", "sandpack entry file"),
        ("script.js", "sandpack script file"),
    ]
    for needle, label in checks:
        report.check(
            needle in html and needle in swift,
            f"{label} present in both reference and fixture ({needle!r})",
        )

    # Chart data must be identical, not merely present.
    html_values = re.search(r"values:\s*\[([0-9,\s.]+)\]", html)
    swift_values = re.search(r"values:\s*\[([0-9,\s.]+)\]", swift)
    if html_values and swift_values:
        left = [float(v) for v in html_values.group(1).split(",")]
        right = [float(v) for v in swift_values.group(1).split(",")]
        report.check(left == right, f"chart series matches the reference: {left}")
    else:
        report.fail("could not locate the chart series in one of the two sources")


# --------------------------------------------------------------------------- #
# 2. Renderer coverage
# --------------------------------------------------------------------------- #


def check_renderer_coverage(root: Path, report: Report) -> None:
    blocks = (root / "App/WarRoomChatBlocks.swift").read_text(encoding="utf-8")
    dispatch_path = root / "App/WarRoomChatBlockRenderer.swift"
    if not dispatch_path.exists():
        report.fail("missing App/WarRoomChatBlockRenderer.swift")
        return
    dispatch = dispatch_path.read_text(encoding="utf-8")

    enum_start = blocks.index("enum ThoxBlock")
    enum_end = blocks.index("\n}", enum_start)
    cases = re.findall(r"^    case ([a-zA-Z]+)", blocks[enum_start:enum_end], flags=re.MULTILINE)
    report.check(bool(cases), f"ThoxBlock declares {len(cases)} cases")

    body_start = dispatch.index("struct ChatBlockView")
    body_end = dispatch.index("\n}", body_start)
    handled = set(re.findall(r"case \.([a-zA-Z]+)", dispatch[body_start:body_end]))

    missing = [c for c in cases if c not in handled]
    report.check(
        not missing,
        "every ThoxBlock case has a renderer arm"
        if not missing
        else f"ThoxBlock cases with no renderer arm: {missing}",
    )


# --------------------------------------------------------------------------- #
# 3. Boundary + token checks
# --------------------------------------------------------------------------- #


def check_boundary(root: Path, report: Report) -> None:
    for relative in CHAT_FILES:
        path = root / relative
        if not path.exists():
            report.fail(f"missing chat-path file: {relative}")
            continue
        text = path.read_text(encoding="utf-8")
        # Strip comments so prose describing the boundary is not a violation.
        code = strip_swift_comments(text)
        hits = [api for api in FORBIDDEN_ON_PRESENTATION_PATH if api in code]
        report.check(
            not hits,
            f"{relative}: no network API on the presentation path"
            if not hits
            else f"{relative}: network API on the presentation path: {hits}",
        )

    for relative in PURE_FILES:
        path = root / relative
        if not path.exists():
            continue
        code = strip_swift_comments(path.read_text(encoding="utf-8"))
        imports = set(re.findall(r"^import ([A-Za-z]+)", code, flags=re.MULTILINE))
        allowed = {"Foundation"}
        report.check(
            imports <= allowed,
            f"{relative}: Foundation-only ({sorted(imports)})"
            if imports <= allowed
            else f"{relative}: must stay Foundation-only, found {sorted(imports - allowed)}",
        )


def check_tokens(root: Path, report: Report) -> None:
    path = root / "App/ThoxTheme.swift"
    if not path.exists():
        report.fail("missing App/ThoxTheme.swift")
        return
    text = path.read_text(encoding="utf-8")
    for name, value in REQUIRED_TOKENS.items():
        pattern = rf"static let {name}\s*=\s*Color\(hex6:\s*{value}\)"
        report.check(
            re.search(pattern, text, flags=re.IGNORECASE) is not None,
            f"token {name} == {value}",
        )


def strip_swift_comments(text: str) -> str:
    """Remove `//` and `/* */` comments. Good enough for an API grep."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    return re.sub(r"//[^\n]*", "", text)


def check_delimiters(root: Path, report: Report) -> None:
    """Balance braces/brackets/parens outside strings and comments.

    Not a compiler, but it reliably catches the single most common way a
    hand-edited Swift file breaks when nobody can build it.
    """
    for relative in CHAT_FILES + ["App/ThoxTheme.swift"]:
        path = root / relative
        if not path.exists():
            continue
        counts = balance(path.read_text(encoding="utf-8"))
        report.check(
            counts == (0, 0, 0),
            f"{relative}: delimiters balanced"
            if counts == (0, 0, 0)
            else f"{relative}: unbalanced (brace,bracket,paren) = {counts}",
        )


def balance(text: str) -> tuple[int, int, int]:
    brace = bracket = paren = 0
    i = 0
    n = len(text)
    in_line_comment = False
    in_block_comment = 0
    in_string = False
    in_multiline_string = False
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
            i += 1
            continue
        if in_block_comment:
            if ch == "*" and nxt == "/":
                in_block_comment -= 1
                i += 2
                continue
            if ch == "/" and nxt == "*":
                in_block_comment += 1
                i += 2
                continue
            i += 1
            continue
        if in_multiline_string:
            if text.startswith('"""', i):
                in_multiline_string = False
                i += 3
                continue
            i += 1
            continue
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                in_string = False
            i += 1
            continue
        if text.startswith('"""', i):
            in_multiline_string = True
            i += 3
            continue
        if ch == '"':
            in_string = True
            i += 1
            continue
        if ch == "/" and nxt == "/":
            in_line_comment = True
            i += 2
            continue
        if ch == "/" and nxt == "*":
            in_block_comment = 1
            i += 2
            continue
        if ch == "{":
            brace += 1
        elif ch == "}":
            brace -= 1
        elif ch == "[":
            bracket += 1
        elif ch == "]":
            bracket -= 1
        elif ch == "(":
            paren += 1
        elif ch == ")":
            paren -= 1
        i += 1
    return brace, bracket, paren


# --------------------------------------------------------------------------- #
# 4. Algorithm cross-checks
# --------------------------------------------------------------------------- #
# Line-for-line ports of the three Foundation-only Swift parsers. They exist so
# the parsing behaviour can be exercised on a host with no Swift toolchain. A
# disagreement between a port and its original is a finding in whichever one is
# wrong — never a reason to weaken this file.


def markdown_nodes(source: str) -> list[tuple]:
    """Port of `ThoxMarkdownDocument.parse`."""
    lines = source.replace("\r\n", "\n").split("\n")
    nodes: list[tuple] = []
    i = 0

    def thematic(line: str) -> bool:
        compact = "".join(c for c in line if not c.isspace())
        return len(compact) >= 3 and (
            set(compact) == {"-"} or set(compact) == {"*"} or set(compact) == {"_"}
        )

    def heading(line: str):
        level = 0
        rest = line
        while rest.startswith("#") and level < 6:
            level += 1
            rest = rest[1:]
        if level == 0:
            return None
        if rest and not rest.startswith(" "):
            return None
        return ("heading", level, rest.strip())

    def unordered(line: str):
        for marker in ("- ", "* ", "+ "):
            if line.startswith(marker):
                return line[len(marker):].strip()
        return "" if line in ("-", "*", "+") else None

    def ordered(line: str):
        digits = ""
        rest = line
        while rest and rest[0].isdigit() and len(digits) < 9:
            digits += rest[0]
            rest = rest[1:]
        if not digits or not rest or rest[0] not in ".)":
            return None
        rest = rest[1:]
        if rest and not rest.startswith(" "):
            return None
        return int(digits), rest.strip()

    def join(existing: str, addition: str) -> str:
        return addition if not existing else existing + " " + addition

    while i < len(lines):
        line = lines[i].strip()
        if not line:
            i += 1
            continue
        if thematic(line):
            nodes.append(("thematicBreak",))
            i += 1
            continue
        h = heading(line)
        if h:
            nodes.append(h)
            i += 1
            continue
        if unordered(line) is not None:
            items = []
            while i < len(lines):
                current = lines[i].strip()
                content = unordered(current)
                if content is not None:
                    items.append(content)
                    i += 1
                    continue
                if current and items and lines[i].startswith(" "):
                    items[-1] = join(items[-1], current)
                    i += 1
                    continue
                break
            nodes.append(("unorderedList", tuple(items)))
            continue
        o = ordered(line)
        if o:
            items = []
            start = o[0]
            while i < len(lines):
                current = lines[i].strip()
                parsed = ordered(current)
                if parsed:
                    items.append(parsed[1])
                    i += 1
                    continue
                if current and items and lines[i].startswith(" "):
                    items[-1] = join(items[-1], current)
                    i += 1
                    continue
                break
            nodes.append(("orderedList", start, tuple(items)))
            continue
        if line.startswith(">"):
            paragraphs = []
            current_paragraph = ""
            while i < len(lines):
                current = lines[i].strip()
                if not current.startswith(">"):
                    break
                content = current[1:]
                if content.startswith(" "):
                    content = content[1:]
                if not content.strip():
                    if current_paragraph:
                        paragraphs.append(current_paragraph)
                        current_paragraph = ""
                else:
                    current_paragraph = join(current_paragraph, content)
                i += 1
            if current_paragraph:
                paragraphs.append(current_paragraph)
            nodes.append(("blockQuote", tuple(paragraphs)))
            continue
        text = ""
        start_index = i
        while i < len(lines):
            current = lines[i].strip()
            if not current:
                break
            if i > start_index and (
                thematic(current)
                or heading(current)
                or unordered(current) is not None
                or ordered(current)
                or current.startswith(">")
            ):
                break
            text = join(text, current)
            i += 1
        if text:
            nodes.append(("paragraph", text))
    return nodes


CONNECTORS = set("-=.><")


def mermaid_parse(source: str):
    """Port of `MermaidFlowchart.parse`. Returns (direction, nodes, edges) or None."""
    statements = [
        s.strip()
        for s in re.split(r"[;\n]", source.replace("\r\n", "\n"))
        if s.strip() and not s.strip().startswith("%%")
    ]
    direction = "LR"
    saw_header = False
    order: list[str] = []
    labels: dict[str, str] = {}
    edges: list[tuple] = []

    def register(node_id: str, label: str) -> None:
        if node_id in labels:
            if labels[node_id] == node_id and label != node_id:
                labels[node_id] = label
            return
        order.append(node_id)
        labels[node_id] = label

    def parse_node(chars: list[str], start: int):
        i = start
        ident = ""
        while i < len(chars) and (chars[i].isalnum() or chars[i] == "_"):
            ident += chars[i]
            i += 1
        if not ident:
            return None
        if i >= len(chars) or chars[i] not in "([{":
            return ident, ident, i
        opener = chars[i]
        opens = {"(": "(", "[": "[", "{": "{"}[opener]
        closes = {"(": ")", "[": "]", "{": "}"}[opener]
        depth = 0
        body = ""
        cursor = i
        quoted = False
        while cursor < len(chars):
            ch = chars[cursor]
            if ch == '"':
                quoted = not quoted
            if not quoted:
                if ch == opens:
                    depth += 1
                if ch == closes:
                    depth -= 1
                    if depth == 0:
                        cursor += 1
                        return ident, normalize(body), cursor
            if depth > 0 and (ch != opens or depth > 1):
                body += ch
            cursor += 1
        return None

    def normalize(raw: str) -> str:
        text = raw.strip()
        while text and text[0] in '[("':
            text = text[1:]
        while text and text[-1] in '])"':
            text = text[:-1]
        return text.strip()

    def parse_connector(chars: list[str], start: int):
        i = start
        run = ""
        while i < len(chars) and chars[i] in CONNECTORS:
            run += chars[i]
            i += 1
        if len(run) < 2:
            return None
        style = "solid"
        if "." in run:
            style = "dotted"
        if "=" in run:
            style = "thick"
        directed = ">" in run or "<" in run
        if i < len(chars) and chars[i] == "|":
            cursor = i + 1
            text = ""
            while cursor < len(chars) and chars[cursor] != "|":
                text += chars[cursor]
                cursor += 1
            if cursor >= len(chars):
                return None
            return normalize(text), style, directed, cursor + 1
        if not directed:
            cursor = i
            text = ""
            while cursor < len(chars) and chars[cursor] not in CONNECTORS:
                if chars[cursor] in "([{":
                    return None, style, False, i
                text += chars[cursor]
                cursor += 1
            second = ""
            while cursor < len(chars) and chars[cursor] in CONNECTORS:
                second += chars[cursor]
                cursor += 1
            if len(second) >= 2 and text.strip():
                if "." in second:
                    style = "dotted"
                if "=" in second:
                    style = "thick"
                return text.strip(), style, ">" in second, cursor
        return None, style, directed, i

    def parse_chain(statement: str):
        chars = list(statement)
        i = 0
        chain_nodes = []
        connectors = []
        while i < len(chars):
            while i < len(chars) and chars[i].isspace():
                i += 1
            if i >= len(chars):
                break
            parsed = parse_node(chars, i)
            if parsed is None:
                return None
            chain_nodes.append((parsed[0], parsed[1]))
            i = parsed[2]
            while i < len(chars) and chars[i].isspace():
                i += 1
            if i >= len(chars):
                break
            connector = parse_connector(chars, i)
            if connector is None:
                return None
            connectors.append(connector[:3])
            i = connector[3]
        if len(connectors) != max(len(chain_nodes) - 1, 0):
            return None
        chain_edges = [
            (chain_nodes[k][0], chain_nodes[k + 1][0], connectors[k][0])
            for k in range(len(connectors))
        ]
        return chain_nodes, chain_edges

    for statement in statements:
        if not saw_header:
            header = re.match(r"^(flowchart|graph)(\s+([A-Za-z]{2}))?\s*(.*)$", statement)
            if header:
                direction = (header.group(3) or "TB").upper()
                saw_header = True
                remainder = header.group(4).strip()
                if not remainder:
                    continue
                statement = remainder
        for unsupported in ("subgraph", "end", "click", "style", "classDef", "class ", "linkStyle"):
            if statement.startswith(unsupported):
                return None
        chain = parse_chain(statement)
        if chain is None:
            return None
        for node_id, label in chain[0]:
            register(node_id, label)
        edges.extend(chain[1])

    if not order:
        return None
    return direction, [(n, labels[n]) for n in order], edges


def mermaid_ranks(nodes, edges) -> list[list[str]]:
    """Port of `MermaidFlowchart.ranks`."""
    level = {n: 0 for n, _ in nodes}
    forward = [(a, b) for a, b, _ in edges if a != b]
    passes = 0
    changed = True
    while changed and passes < len(nodes):
        changed = False
        passes += 1
        for a, b in forward:
            if level[a] + 1 > level[b]:
                level[b] = level[a] + 1
                changed = True
    depth = max(level.values(), default=0) + 1
    buckets: list[list[str]] = [[] for _ in range(depth)]
    for n, _ in nodes:
        buckets[min(level[n], depth - 1)].append(n)
    return [b for b in buckets if b]


def check_algorithms(report: Report) -> None:
    # -- Markdown: the golden reference's first block is prose + a real list. --
    golden_markdown = (
        "**ThoxOS chat** renders a typed block stream. This paragraph is Markdown "
        "with a list, an inline `code` span, and math:\n\n"
        "- sanitized HTML (DOMPurify)\n"
        "- syntax-highlighted code\n"
        "- KaTeX: ∫₀¹ x² dx = 1⁄3"
    )
    nodes = markdown_nodes(golden_markdown)
    report.check(
        len(nodes) == 2 and nodes[0][0] == "paragraph" and nodes[1][0] == "unorderedList",
        f"markdown: golden prose splits into paragraph + list (got {[n[0] for n in nodes]})",
    )
    report.check(
        len(nodes) == 2 and len(nodes[1][1]) == 3,
        "markdown: the golden list has three items",
    )

    mixed = "# Title\n\nIntro line\n- one\n- two\n\n1. first\n2. second\n\n> quoted\n\n---\n\ntail"
    kinds = [n[0] for n in markdown_nodes(mixed)]
    report.check(
        kinds
        == [
            "heading",
            "paragraph",
            "unorderedList",
            "orderedList",
            "blockQuote",
            "thematicBreak",
            "paragraph",
        ],
        f"markdown: mixed document segments correctly (got {kinds})",
    )
    report.check(
        markdown_nodes("#hashtag not a heading")[0][0] == "paragraph",
        "markdown: `#hashtag` is prose, not a heading",
    )
    report.check(markdown_nodes("   \n\n  ") == [], "markdown: whitespace-only input yields no nodes")

    # -- Mermaid: the exact source in the golden reference. --
    golden_mermaid = (
        "graph LR; U[User]-->C[ThoxOS Chat]; C-->R[ThoxRoute]; "
        "R-->O[ox-alpha]; R-->L[Local model]"
    )
    parsed = mermaid_parse(golden_mermaid)
    if parsed is None:
        report.fail("mermaid: the golden diagram source failed to parse")
    else:
        direction, nodes, edges = parsed
        report.check(direction == "LR", f"mermaid: direction parsed as {direction}")
        labels = [label for _, label in nodes]
        report.check(
            labels == ["User", "ThoxOS Chat", "ThoxRoute", "ox-alpha", "Local model"],
            f"mermaid: node labels parsed as {labels}",
        )
        report.check(len(edges) == 4, f"mermaid: {len(edges)} edges parsed (expected 4)")
        ranks = mermaid_ranks(nodes, edges)
        report.check(
            ranks == [["U"], ["C"], ["R"], ["O", "L"]],
            f"mermaid: layered layout is {ranks}",
        )

    labelled = mermaid_parse("graph TD; A[Start] -->|yes| B[Stop]")
    report.check(
        labelled is not None and labelled[2][0][2] == "yes",
        "mermaid: pipe-delimited edge labels are captured",
    )
    labelled2 = mermaid_parse("graph LR; A -- retry --> B")
    report.check(
        labelled2 is not None and labelled2[2][0][2] == "retry",
        "mermaid: `-- label -->` edge labels are captured",
    )
    report.check(
        mermaid_parse("graph LR; subgraph one\n A-->B\n end") is None,
        "mermaid: unsupported `subgraph` degrades to the source pane",
    )
    report.check(
        mermaid_parse("graph LR; A-->") is None,
        "mermaid: a trailing connector degrades to the source pane",
    )
    cyclic = mermaid_parse("graph LR; A-->B; B-->A")
    report.check(
        cyclic is not None and mermaid_ranks(cyclic[1], cyclic[2]),
        "mermaid: a cyclic graph still terminates and lays out",
    )


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default=".", type=Path)
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--json", action="store_true", help="emit machine-readable output")
    args = parser.parse_args()

    root = args.repo_root.resolve()
    if not (root / "App").is_dir():
        print(f"error: {root} is not a ThoxWarRoom checkout", file=sys.stderr)
        return 2

    report = Report()
    check_fixture_parity(root, report)
    check_renderer_coverage(root, report)
    check_boundary(root, report)
    check_tokens(root, report)
    check_delimiters(root, report)
    check_algorithms(report)

    if args.json:
        print(json.dumps({"passed": report.passed, "findings": report.findings}, indent=2))
    else:
        if args.verbose:
            for line in report.passed:
                print(f"  ok   {line}")
        for line in report.findings:
            print(f"  FAIL {line}")
        print(
            f"\n{len(report.passed)} checks passed, {len(report.findings)} findings"
        )

    return 1 if report.findings else 0


if __name__ == "__main__":
    raise SystemExit(main())

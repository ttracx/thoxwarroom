import XCTest
@testable import ThoxWarRoom

/// Coverage for the three Foundation-only parsers behind the chat surface.
///
/// These types were extracted from the view layer specifically so they could be
/// tested without a host UI, a network, or a running provider. Every assertion
/// here is deterministic and offline.
final class WarRoomChatRenderingTests: XCTestCase {

    // MARK: - ThoxMarkdownDocument

    func testMarkdownSplitsHeadingParagraphAndList() {
        let document = ThoxMarkdownDocument.parse(
            """
            # Title

            Body prose here.

            - one
            - two
            - three
            """
        )
        XCTAssertEqual(document.nodes.count, 3)
        if case let .heading(level, text) = document.nodes[0] {
            XCTAssertEqual(level, 1)
            XCTAssertEqual(text, "Title")
        } else {
            XCTFail("Expected leading heading, got \(document.nodes[0])")
        }
        if case let .paragraph(prose) = document.nodes[1] {
            XCTAssertEqual(prose, "Body prose here.")
        } else {
            XCTFail("Expected paragraph, got \(document.nodes[1])")
        }
        if case let .unorderedList(items) = document.nodes[2] {
            XCTAssertEqual(items, ["one", "two", "three"])
        } else {
            XCTFail("Expected unordered list, got \(document.nodes[2])")
        }
    }

    func testMarkdownOrderedListPreservesStartingNumber() {
        let document = ThoxMarkdownDocument.parse(
            """
            3. first
            4. second
            """
        )
        XCTAssertEqual(document.nodes.count, 1)
        if case let .orderedList(start, items) = document.nodes[0] {
            XCTAssertEqual(start, 3)
            XCTAssertEqual(items, ["first", "second"])
        } else {
            XCTFail("Expected ordered list, got \(document.nodes[0])")
        }
    }

    func testMarkdownBlockQuoteJoinsSoftLines() {
        let document = ThoxMarkdownDocument.parse(
            """
            > quoted line one
            > line two
            """
        )
        if case let .blockQuote(paragraphs) = document.nodes.first {
            XCTAssertEqual(paragraphs, ["quoted line one line two"])
        } else {
            XCTFail("Expected block quote, got \(String(describing: document.nodes.first))")
        }
    }

    func testMarkdownThematicBreakIsRecognized() {
        let document = ThoxMarkdownDocument.parse("prose\n\n---\n\nmore")
        XCTAssertEqual(document.nodes.count, 3)
        XCTAssertEqual(document.nodes[1], .thematicBreak)
    }

    // MARK: - ThoxSyntaxHighlighter

    func testSyntaxHighlighterIsLosslessForSupportedLanguage() {
        let source = """
        // greet
        func greet(name: String) -> String {
            return "Hello, \\(name)!"
        }
        """
        let tokens = ThoxSyntaxHighlighter.tokenize(source, language: "swift")
        XCTAssertEqual(tokens.map(\.text).joined(), source)
        XCTAssertTrue(tokens.contains(where: { $0.kind == .keyword && $0.text == "func" }))
        XCTAssertTrue(tokens.contains(where: { $0.kind == .comment && $0.text.hasPrefix("//") }))
    }

    func testSyntaxHighlighterFallsBackToPlainForUnknownLanguage() {
        let source = "arbitrary\ntext\n"
        let tokens = ThoxSyntaxHighlighter.tokenize(source, language: "brainfuck")
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens.first?.kind, .plain)
        XCTAssertEqual(tokens.first?.text, source)
    }

    func testSyntaxHighlighterMarkupSplitsTagsAndText() {
        let tokens = ThoxSyntaxHighlighter.tokenize("<b class=\"x\">hi</b>", language: "html")
        XCTAssertEqual(tokens.map(\.text).joined(), "<b class=\"x\">hi</b>")
        XCTAssertTrue(tokens.contains(where: { $0.kind == .keyword && $0.text == "b" }))
        XCTAssertTrue(tokens.contains(where: { $0.kind == .string && $0.text.contains("\"x\"") }))
    }

    // MARK: - MermaidFlowchart

    func testMermaidParsesGoldenFlowchart() {
        let source = "graph LR; U[User]-->C[ThoxOS Chat]; C-->R[ThoxRoute]; R-->O[ox-alpha]; R-->L[Local model]"
        let flowchart = MermaidFlowchart.parse(source)
        XCTAssertNotNil(flowchart)
        XCTAssertEqual(flowchart?.direction, .leftRight)
        XCTAssertEqual(flowchart?.nodes.count, 5)
        XCTAssertEqual(flowchart?.edges.count, 4)
        // Ranks should progress: [U], [C], [R], [O, L].
        let ranks = flowchart?.ranks ?? []
        XCTAssertEqual(ranks.count, 4)
        XCTAssertEqual(ranks.last?.map(\.id).sorted(), ["L", "O"])
    }

    func testMermaidRejectsUnsupportedSubgraphSyntax() {
        let source = """
        graph TD
        subgraph cluster
        A --> B
        end
        """
        XCTAssertNil(MermaidFlowchart.parse(source))
    }

    // MARK: - SandpackSpec composed document

    func testSandpackComposedDocumentEmbedsHTMLAndNeutralisesScriptClose() {
        let spec = SandpackSpec(
            template: "vanilla",
            fileOrder: ["index.html", "script.js"],
            files: [
                "index.html": "<h1>hi</h1>",
                "script.js": "console.log('</script>');"
            ]
        )
        let document = spec.composedDocument()
        XCTAssertTrue(document.contains("<h1>hi</h1>"))
        // The literal `</script` sequence inside the JS file must be neutralised
        // so a scripted file cannot close its own tag and inject markup.
        XCTAssertFalse(document.contains("console.log('</script>')"))
        XCTAssertTrue(document.contains("<\\/script"))
    }
}

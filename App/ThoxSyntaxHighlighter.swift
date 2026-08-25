// ThoxSyntaxHighlighter.swift
// Deterministic, dependency-free syntax tokenizer for chat code blocks.
//
// WHY THIS EXISTS
// ---------------
// The golden reference and the ThoxMythos product surface both highlight code
// (highlight.js and Prism respectively). Neither is available to us: shipping a
// JavaScript highlighter would mean putting a script-executing web view in the
// middle of the transcript, which is exactly the surface the audit boundary
// keeps out of the chat path. So the native surface tokenizes in Swift.
//
// GUARANTEES
// ----------
//   * Total — every input produces tokens; unknown languages fall back to a
//     single `.plain` token.
//   * Lossless — `tokenize(s, language: l).map(\.text).joined() == s` for every
//     input and language. This is asserted in `WarRoomChatSurfaceTests`.
//   * Pure — no Foundation regex, no locale, no allocation of the source, and
//     no behavior that varies between runs, platforms, or OS versions.
//
// It is a *presentation* tokenizer, not a parser: it is allowed to mis-colour
// pathological input, but it is never allowed to lose or reorder it.

import Foundation

enum ThoxSyntaxHighlighter {
    /// Semantic class for one contiguous run of source text.
    enum TokenKind: String, Equatable, Hashable, CaseIterable {
        case plain
        case comment
        case string
        case number
        case keyword
        case type
        case punctuation
    }

    /// One contiguous run of source text with a single semantic class.
    struct Token: Equatable, Hashable {
        let kind: TokenKind
        let text: String
    }

    /// Longest source we will tokenize. Beyond this the block renders plain, so
    /// a pathological paste cannot make the transcript janky.
    static let maximumHighlightedLength = 40_000

    // MARK: - Entry point

    /// Tokenizes `source` using the profile for `language`.
    ///
    /// - Parameters:
    ///   - source: Raw code exactly as it will be displayed.
    ///   - language: A fence language tag, case-insensitive. Unknown tags are
    ///     treated as plain text.
    static func tokenize(_ source: String, language: String) -> [Token] {
        guard !source.isEmpty else { return [] }
        guard source.count <= maximumHighlightedLength else {
            return [Token(kind: .plain, text: source)]
        }

        switch Resolution.resolve(language) {
        case .unsupported:
            return [Token(kind: .plain, text: source)]
        case .markup:
            return Markup.tokenize(Array(source))
        case .scanned(let profile):
            return Scanner(characters: Array(source), profile: profile).run()
        }
    }

    /// True when `language` has a real profile — used by the view to decide
    /// whether the "plain text" affordance is honest.
    static func isHighlightable(_ language: String) -> Bool {
        if case .unsupported = Resolution.resolve(language) { return false }
        return true
    }

    /// How a fence tag maps onto a tokenizer. `Profile` itself is not
    /// `Equatable` (it holds an optional tuple), so the routing decision lives
    /// in its own enum rather than being pattern-matched on the profile.
    enum Resolution {
        case unsupported
        case markup
        case scanned(Profile)

        static func resolve(_ language: String) -> Resolution {
            switch language.lowercased().trimmingCharacters(in: .whitespaces) {
            case "swift":
                return .scanned(.swift)
            case "typescript", "ts", "tsx", "javascript", "js", "jsx", "json5":
                return .scanned(.ecmascript)
            case "json":
                return .scanned(.json)
            case "python", "py":
                return .scanned(.python)
            case "bash", "sh", "shell", "zsh":
                return .scanned(.shell)
            case "css":
                return .scanned(.css)
            case "html", "xml", "svg":
                return .markup
            default:
                return .unsupported
            }
        }
    }

    // MARK: - Language profiles

    struct Profile {
        /// Prefixes that start a comment running to end of line.
        let lineComments: [String]
        /// Delimiters for a block comment, if the language has one.
        let blockComment: (open: String, close: String)?
        /// Quote characters that open a string literal.
        let stringDelimiters: Set<Character>
        /// Whether a backslash escapes the next character inside a string.
        let usesBackslashEscapes: Bool
        /// Whether `"""` opens a multi-line string (Swift, Python).
        let usesTripleQuotes: Bool
        /// Reserved words rendered as keywords.
        let keywords: Set<String>
        /// Identifiers rendered as types regardless of casing.
        let literalTypes: Set<String>
        /// Whether a leading uppercase identifier is treated as a type.
        let capitalizedIdentifiersAreTypes: Bool

        static let swift = Profile(
            lineComments: ["//"],
            blockComment: ("/*", "*/"),
            stringDelimiters: ["\""],
            usesBackslashEscapes: true,
            usesTripleQuotes: true,
            keywords: [
                "actor", "any", "as", "associatedtype", "async", "await", "break", "case",
                "catch", "class", "continue", "default", "defer", "deinit", "do", "else",
                "enum", "extension", "fallthrough", "false", "fileprivate", "for", "func",
                "guard", "if", "import", "in", "init", "inout", "internal", "is", "let",
                "nil", "open", "operator", "private", "protocol", "public", "repeat",
                "return", "self", "Self", "some", "static", "struct", "subscript", "super",
                "switch", "throw", "throws", "true", "try", "typealias", "var", "where",
                "while", "nonisolated", "final", "lazy", "weak", "unowned", "mutating"
            ],
            literalTypes: [],
            capitalizedIdentifiersAreTypes: true
        )

        static let ecmascript = Profile(
            lineComments: ["//"],
            blockComment: ("/*", "*/"),
            stringDelimiters: ["\"", "'", "`"],
            usesBackslashEscapes: true,
            usesTripleQuotes: false,
            keywords: [
                "abstract", "as", "async", "await", "break", "case", "catch", "class",
                "const", "continue", "declare", "default", "delete", "do", "else", "enum",
                "export", "extends", "false", "finally", "for", "from", "function", "get",
                "if", "implements", "import", "in", "instanceof", "interface", "let", "new",
                "null", "of", "private", "protected", "public", "readonly", "return", "set",
                "static", "super", "switch", "this", "throw", "true", "try", "type",
                "typeof", "undefined", "var", "void", "while", "yield"
            ],
            literalTypes: [
                "string", "number", "boolean", "bigint", "symbol", "object", "unknown",
                "never", "any", "Promise", "Array", "Record", "Partial"
            ],
            capitalizedIdentifiersAreTypes: true
        )

        static let json = Profile(
            lineComments: [],
            blockComment: nil,
            stringDelimiters: ["\""],
            usesBackslashEscapes: true,
            usesTripleQuotes: false,
            keywords: ["true", "false", "null"],
            literalTypes: [],
            capitalizedIdentifiersAreTypes: false
        )

        static let python = Profile(
            lineComments: ["#"],
            blockComment: nil,
            stringDelimiters: ["\"", "'"],
            usesBackslashEscapes: true,
            usesTripleQuotes: true,
            keywords: [
                "and", "as", "assert", "async", "await", "break", "class", "continue",
                "def", "del", "elif", "else", "except", "False", "finally", "for", "from",
                "global", "if", "import", "in", "is", "lambda", "None", "nonlocal", "not",
                "or", "pass", "raise", "return", "True", "try", "while", "with", "yield"
            ],
            literalTypes: ["int", "str", "float", "bool", "bytes", "list", "dict", "set", "tuple"],
            capitalizedIdentifiersAreTypes: true
        )

        static let shell = Profile(
            lineComments: ["#"],
            blockComment: nil,
            stringDelimiters: ["\"", "'"],
            usesBackslashEscapes: true,
            usesTripleQuotes: false,
            keywords: [
                "case", "do", "done", "elif", "else", "esac", "export", "fi", "for",
                "function", "if", "in", "local", "readonly", "return", "set", "then",
                "until", "while", "echo", "cd", "exit", "source"
            ],
            literalTypes: [],
            capitalizedIdentifiersAreTypes: false
        )

        static let css = Profile(
            lineComments: [],
            blockComment: ("/*", "*/"),
            stringDelimiters: ["\"", "'"],
            usesBackslashEscapes: true,
            usesTripleQuotes: false,
            keywords: [
                "important", "media", "supports", "keyframes", "import", "from", "to",
                "root", "hover", "focus", "active"
            ],
            literalTypes: [],
            capitalizedIdentifiersAreTypes: false
        )
    }

    // MARK: - Generic scanner

    private struct Scanner {
        let characters: [Character]
        let profile: Profile

        func run() -> [Token] {
            var tokens: [Token] = []
            var pending = ""
            var index = 0

            func flushPending() {
                if !pending.isEmpty {
                    tokens.append(Token(kind: .plain, text: pending))
                    pending = ""
                }
            }

            while index < characters.count {
                let character = characters[index]

                if let comment = matchLineComment(at: index) {
                    flushPending()
                    tokens.append(Token(kind: .comment, text: comment.text))
                    index = comment.end
                    continue
                }

                if let comment = matchBlockComment(at: index) {
                    flushPending()
                    tokens.append(Token(kind: .comment, text: comment.text))
                    index = comment.end
                    continue
                }

                if profile.stringDelimiters.contains(character) {
                    let literal = matchString(at: index, quote: character)
                    flushPending()
                    tokens.append(Token(kind: .string, text: literal.text))
                    index = literal.end
                    continue
                }

                if character.isNumber, isNumberStart(at: index) {
                    let literal = matchNumber(at: index)
                    flushPending()
                    tokens.append(Token(kind: .number, text: literal.text))
                    index = literal.end
                    continue
                }

                if isIdentifierStart(character) {
                    let word = matchIdentifier(at: index)
                    let kind = classify(word.text)
                    if kind == .plain {
                        pending += word.text
                    } else {
                        flushPending()
                        tokens.append(Token(kind: kind, text: word.text))
                    }
                    index = word.end
                    continue
                }

                if Self.punctuation.contains(character) {
                    flushPending()
                    tokens.append(Token(kind: .punctuation, text: String(character)))
                    index += 1
                    continue
                }

                pending.append(character)
                index += 1
            }

            flushPending()
            return tokens
        }

        private static let punctuation: Set<Character> = [
            "{", "}", "(", ")", "[", "]", ";", ",", ".", ":", "=", "+", "-", "*",
            "/", "<", ">", "!", "?", "&", "|", "%", "^", "~"
        ]

        private func classify(_ word: String) -> TokenKind {
            if profile.keywords.contains(word) { return .keyword }
            if profile.literalTypes.contains(word) { return .type }
            if profile.capitalizedIdentifiersAreTypes,
               let first = word.first,
               first.isUppercase {
                return .type
            }
            return .plain
        }

        private func isIdentifierStart(_ character: Character) -> Bool {
            character.isLetter || character == "_" || character == "$" || character == "@"
        }

        private func isIdentifierBody(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_" || character == "$"
        }

        /// A digit only starts a number when it is not in the middle of an
        /// identifier (`utf8` must not colour its `8`).
        private func isNumberStart(at index: Int) -> Bool {
            guard index > 0 else { return true }
            return !isIdentifierBody(characters[index - 1])
        }

        private func matchIdentifier(at start: Int) -> (text: String, end: Int) {
            var index = start + 1
            while index < characters.count, isIdentifierBody(characters[index]) {
                index += 1
            }
            return (String(characters[start..<index]), index)
        }

        private func matchNumber(at start: Int) -> (text: String, end: Int) {
            var index = start
            var seenSeparator = false
            while index < characters.count {
                let character = characters[index]
                if character.isHexDigit || character == "x" || character == "X" ||
                    character == "b" || character == "o" || character == "_" {
                    index += 1
                    continue
                }
                if character == ".", !seenSeparator,
                   index + 1 < characters.count, characters[index + 1].isNumber {
                    seenSeparator = true
                    index += 1
                    continue
                }
                break
            }
            return (String(characters[start..<index]), index)
        }

        private func matchLineComment(at start: Int) -> (text: String, end: Int)? {
            for marker in profile.lineComments where matches(marker, at: start) {
                var index = start
                while index < characters.count, characters[index] != "\n" {
                    index += 1
                }
                return (String(characters[start..<index]), index)
            }
            return nil
        }

        private func matchBlockComment(at start: Int) -> (text: String, end: Int)? {
            guard let delimiters = profile.blockComment, matches(delimiters.open, at: start) else {
                return nil
            }
            let close = Array(delimiters.close)
            var index = start + delimiters.open.count
            while index < characters.count {
                if matches(close, at: index) {
                    index += close.count
                    return (String(characters[start..<index]), index)
                }
                index += 1
            }
            // Unterminated block comment: colour to end of source rather than
            // dropping it.
            return (String(characters[start...]), characters.count)
        }

        private func matchString(at start: Int, quote: Character) -> (text: String, end: Int) {
            // Triple-quoted literals close only on a matching triple.
            if profile.usesTripleQuotes,
               start + 2 < characters.count,
               characters[start + 1] == quote,
               characters[start + 2] == quote {
                var index = start + 3
                while index + 2 < characters.count {
                    if characters[index] == quote,
                       characters[index + 1] == quote,
                       characters[index + 2] == quote {
                        return (String(characters[start...(index + 2)]), index + 3)
                    }
                    index += 1
                }
                return (String(characters[start...]), characters.count)
            }

            var index = start + 1
            while index < characters.count {
                let character = characters[index]
                if profile.usesBackslashEscapes, character == "\\", index + 1 < characters.count {
                    index += 2
                    continue
                }
                if character == quote {
                    return (String(characters[start...index]), index + 1)
                }
                // A single-line literal never crosses a newline; treating the
                // newline as the terminator keeps an unterminated quote from
                // swallowing the rest of the block.
                if character == "\n" {
                    return (String(characters[start..<index]), index)
                }
                index += 1
            }
            return (String(characters[start...]), characters.count)
        }

        private func matches(_ needle: String, at index: Int) -> Bool {
            matches(Array(needle), at: index)
        }

        private func matches(_ needle: [Character], at index: Int) -> Bool {
            guard !needle.isEmpty, index + needle.count <= characters.count else { return false }
            for offset in 0..<needle.count where characters[index + offset] != needle[offset] {
                return false
            }
            return true
        }
    }

    // MARK: - Markup scanner

    /// HTML/XML/SVG need a tag-aware pass rather than a keyword table: tag
    /// names, attribute names, and attribute values each get a different class,
    /// and text between tags stays plain.
    private enum Markup {
        static func tokenize(_ characters: [Character]) -> [Token] {
            var tokens: [Token] = []
            var pending = ""
            var index = 0

            func flushPending() {
                if !pending.isEmpty {
                    tokens.append(Token(kind: .plain, text: pending))
                    pending = ""
                }
            }

            while index < characters.count {
                guard characters[index] == "<" else {
                    pending.append(characters[index])
                    index += 1
                    continue
                }

                flushPending()

                // Comment: `<!-- … -->`
                if hasPrefix("<!--", characters, at: index) {
                    var end = index + 4
                    while end < characters.count, !hasPrefix("-->", characters, at: end) {
                        end += 1
                    }
                    end = min(end + 3, characters.count)
                    tokens.append(Token(kind: .comment, text: String(characters[index..<end])))
                    index = end
                    continue
                }

                // Find the end of the tag; an unterminated tag runs to the end.
                var tagEnd = index + 1
                while tagEnd < characters.count, characters[tagEnd] != ">" {
                    tagEnd += 1
                }
                let inclusiveEnd = min(tagEnd + 1, characters.count)
                tokens.append(contentsOf: tag(Array(characters[index..<inclusiveEnd])))
                index = inclusiveEnd
            }

            flushPending()
            return tokens
        }

        /// Splits one `<…>` run into punctuation / tag name / attributes.
        private static func tag(_ characters: [Character]) -> [Token] {
            var tokens: [Token] = []
            var index = 0
            var sawName = false

            func take(while predicate: (Character) -> Bool) -> String {
                let start = index
                while index < characters.count, predicate(characters[index]) { index += 1 }
                return String(characters[start..<index])
            }

            while index < characters.count {
                let character = characters[index]

                if character.isWhitespace {
                    tokens.append(Token(kind: .plain, text: take(while: { $0.isWhitespace })))
                    continue
                }

                if character == "<" || character == ">" || character == "/" ||
                    character == "!" || character == "?" || character == "=" {
                    tokens.append(Token(kind: .punctuation, text: String(character)))
                    index += 1
                    continue
                }

                if character == "\"" || character == "'" {
                    let quote = character
                    let start = index
                    index += 1
                    while index < characters.count, characters[index] != quote { index += 1 }
                    index = min(index + 1, characters.count)
                    tokens.append(Token(kind: .string, text: String(characters[start..<index])))
                    continue
                }

                let word = take(while: { !$0.isWhitespace && $0 != ">" && $0 != "=" && $0 != "/" })
                if word.isEmpty {
                    // Defensive: never spin without consuming.
                    tokens.append(Token(kind: .plain, text: String(character)))
                    index += 1
                    continue
                }
                tokens.append(Token(kind: sawName ? .type : .keyword, text: word))
                sawName = true
            }

            return tokens
        }

        private static func hasPrefix(_ needle: String, _ characters: [Character], at index: Int) -> Bool {
            let pattern = Array(needle)
            guard index + pattern.count <= characters.count else { return false }
            for offset in 0..<pattern.count where characters[index + offset] != pattern[offset] {
                return false
            }
            return true
        }
    }
}

import Foundation
import XCTest
@testable import WarRoomAppleInfrastructure

final class BoundedHTTP1CodecTests: XCTestCase {
    func testRequestSerializationAddsLengthAndPreservesOriginFormQuery() throws {
        let request = BoundedHTTP1Request(
            method: "POST",
            target: "/v1/run?wait=false",
            headers: [
                .init(name: "Host", value: "private.example"),
                .init(name: "Content-Type", value: "application/json"),
            ],
            body: Data("{}".utf8)
        )
        XCTAssertEqual(
            String(decoding: try BoundedHTTP1RequestSerializer.serialize(request), as: UTF8.self),
            "POST /v1/run?wait=false HTTP/1.1\r\nHost: private.example\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}"
        )
    }

    func testRequestSerializationRejectsInjectionAndAmbiguousFraming() throws {
        XCTAssertThrowsError(try BoundedHTTP1RequestSerializer.serialize(.init(method: "GET\r\nX", target: "/"))) {
            XCTAssertEqual($0 as? BoundedHTTP1Error, .invalidMethod)
        }
        XCTAssertThrowsError(try BoundedHTTP1RequestSerializer.serialize(.init(method: "GET", target: "https://evil/"))) {
            XCTAssertEqual($0 as? BoundedHTTP1Error, .invalidRequestTarget)
        }
        for invalidTarget in ["//authority", "/bad\\path", "/bad%2", "/bad#fragment"] {
            XCTAssertThrowsError(try BoundedHTTP1RequestSerializer.serialize(.init(method: "GET", target: invalidTarget))) {
                XCTAssertEqual($0 as? BoundedHTTP1Error, .invalidRequestTarget)
            }
        }
        XCTAssertThrowsError(try BoundedHTTP1RequestSerializer.serialize(.init(
            method: "GET", target: "/", headers: [.init(name: "X-Test", value: "ok\r\nInjected: yes")]
        ))) {
            XCTAssertEqual($0 as? BoundedHTTP1Error, .invalidHeader)
        }
        XCTAssertThrowsError(try BoundedHTTP1RequestSerializer.serialize(.init(
            method: "POST", target: "/", headers: [.init(name: "Transfer-Encoding", value: "chunked")]
        ))) {
            XCTAssertEqual($0 as? BoundedHTTP1Error, .forbiddenRequestFraming)
        }
        XCTAssertThrowsError(try BoundedHTTP1RequestSerializer.serialize(.init(
            method: "POST", target: "/", headers: [.init(name: "Content-Length", value: "1")], body: Data("xx".utf8)
        ))) {
            XCTAssertEqual($0 as? BoundedHTTP1Error, .ambiguousFraming)
        }
    }

    func testFragmentedFixedLengthResponseDeliversBoundedChunks() throws {
        let limits = try BoundedHTTP1Limits(maximumBodyBytes: 20, maximumDeliveryBytes: 3)
        var parser = try BoundedHTTP1ResponseParser(requestMethod: "GET", limits: limits)
        var events: [BoundedHTTP1ResponseEvent] = []
        for fragment in ["HTTP/1.", "1 200 OK\r", "\nContent-Length: 7\r\nX-A: b\r\n\r\nabcdefg"] {
            events += try parser.receive(Data(fragment.utf8))
        }
        XCTAssertEqual(events, [
            .head(.init(version: "HTTP/1.1", statusCode: 200, reasonPhrase: "OK", headers: [
                .init(name: "Content-Length", value: "7"), .init(name: "X-A", value: "b"),
            ])),
            .body(Data("abc".utf8)), .body(Data("def".utf8)), .body(Data("g".utf8)), .complete,
        ])
        XCTAssertTrue(parser.isComplete)
    }

    func testInformationalThenFinalResponse() throws {
        var parser = try BoundedHTTP1ResponseParser(requestMethod: "POST")
        let wire = "HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 201 Created\r\nContent-Length: 0\r\n\r\n"
        XCTAssertEqual(try parser.receive(Data(wire.utf8)), [
            .informational(.init(version: "HTTP/1.1", statusCode: 100, reasonPhrase: "Continue", headers: [])),
            .head(.init(version: "HTTP/1.1", statusCode: 201, reasonPhrase: "Created", headers: [
                .init(name: "Content-Length", value: "0"),
            ])),
            .complete,
        ])
    }

    func testRejectsFramingOnInformationalResponse() throws {
        try assertParseError(
            "HTTP/1.1 100 Continue\r\nContent-Length: 0\r\n\r\n",
            .forbiddenResponseBody
        )
        try assertParseError(
            "HTTP/1.1 103 Early Hints\r\nTransfer-Encoding: chunked\r\n\r\n",
            .forbiddenResponseBody
        )
    }

    func testLargeCallerChunkIsProcessedIncrementally() throws {
        let limits = try BoundedHTTP1Limits(
            maximumHeaderBytes: 64,
            maximumHeaderCount: 4,
            maximumLineBytes: 32,
            maximumBodyBytes: 128 * 1_024,
            maximumDeliveryBytes: 1_024
        )
        var parser = try BoundedHTTP1ResponseParser(requestMethod: "GET", limits: limits)
        let body = Data(repeating: 0x61, count: limits.maximumBodyBytes)
        var wire = Data("HTTP/1.1 200 OK\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
        wire.append(body)

        let events = try parser.receive(wire)
        let delivered = events.reduce(into: 0) { count, event in
            if case let .body(chunk) = event {
                XCTAssertLessThanOrEqual(chunk.count, limits.maximumDeliveryBytes)
                count += chunk.count
            }
        }
        XCTAssertEqual(delivered, body.count)
        XCTAssertEqual(events.last, .complete)
    }

    func testChunkedResponseIsIncrementalAndRejectsTrailers() throws {
        let limits = try BoundedHTTP1Limits(maximumBodyBytes: 20, maximumDeliveryBytes: 2)
        var parser = try BoundedHTTP1ResponseParser(requestMethod: "GET", limits: limits)
        let events = try parser.receive(Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n0\r\n\r\n".utf8))
        XCTAssertEqual(Array(events.suffix(3)), [
            .body(Data("Wi".utf8)), .body(Data("ki".utf8)), .complete,
        ])
        XCTAssertEqual(events.compactMap { event -> Data? in
            if case let .body(data) = event { return data }
            return nil
        }.reduce(Data(), +), Data("Wiki".utf8))

        var trailers = try BoundedHTTP1ResponseParser(requestMethod: "GET")
        XCTAssertThrowsError(try trailers.receive(Data(
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\nDigest: no\r\n\r\n".utf8
        ))) {
            XCTAssertEqual($0 as? BoundedHTTP1Error, .trailersNotAllowed)
        }
    }

    func testEOFFramingCompletesOnlyAtEOF() throws {
        var parser = try BoundedHTTP1ResponseParser(requestMethod: "GET")
        XCTAssertEqual(try parser.receive(Data("HTTP/1.0 200 OK\r\n\r\nhello".utf8)), [
            .head(.init(version: "HTTP/1.0", statusCode: 200, reasonPhrase: "OK", headers: [])),
            .body(Data("hello".utf8)),
        ])
        XCTAssertEqual(try parser.finishEOF(), [.complete])
    }

    func testRejectsConflictingAndAmbiguousFraming() throws {
        try assertParseError(
            "HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n",
            .ambiguousFraming
        )
        try assertParseError(
            "HTTP/1.1 200 OK\r\nContent-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\n",
            .ambiguousFraming
        )
        try assertParseError(
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip, chunked\r\n\r\n",
            .unsupportedTransferEncoding
        )
        try assertParseError(
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nTransfer-Encoding: chunked\r\n\r\n",
            .unsupportedTransferEncoding
        )
    }

    func testRejectsObsFoldInvalidCRLFAndCaps() throws {
        try assertParseError("HTTP/1.1 200 OK\r\nX: one\r\n two\r\n\r\n", .invalidHeader)
        try assertParseError("HTTP/1.1 200 OK\n\n", .malformedLineEnding)

        let shortLine = try BoundedHTTP1Limits(
            maximumHeaderBytes: 32,
            maximumHeaderCount: 4,
            maximumLineBytes: 12,
            maximumBodyBytes: 10,
            maximumDeliveryBytes: 2
        )
        var parser = try BoundedHTTP1ResponseParser(requestMethod: "GET", limits: shortLine)
        XCTAssertThrowsError(try parser.receive(Data("HTTP/1.1 200 Way Too Long\r\n".utf8))) {
            XCTAssertEqual($0 as? BoundedHTTP1Error, .lineTooLong(limit: 12))
        }

        let oneHeader = try BoundedHTTP1Limits(maximumHeaderCount: 1)
        var countParser = try BoundedHTTP1ResponseParser(requestMethod: "GET", limits: oneHeader)
        XCTAssertThrowsError(try countParser.receive(Data("HTTP/1.1 200 OK\r\nA: 1\r\nB: 2\r\n\r\n".utf8))) {
            XCTAssertEqual($0 as? BoundedHTTP1Error, .tooManyHeaders(limit: 1))
        }

        let shortHeaders = try BoundedHTTP1Limits(
            maximumHeaderBytes: 24,
            maximumHeaderCount: 4,
            maximumLineBytes: 20,
            maximumBodyBytes: 10,
            maximumDeliveryBytes: 2
        )
        var byteParser = try BoundedHTTP1ResponseParser(requestMethod: "GET", limits: shortHeaders)
        XCTAssertThrowsError(try byteParser.receive(Data("HTTP/1.1 200 OK\r\nX: 1234\r\n\r\n".utf8))) {
            XCTAssertEqual($0 as? BoundedHTTP1Error, .headersTooLarge(limit: 24))
        }
    }

    func testRejectsForbiddenBodiesAndOverflows() throws {
        var head = try BoundedHTTP1ResponseParser(requestMethod: "HEAD")
        XCTAssertEqual(try head.receive(Data("HTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\n".utf8)), [
            .head(.init(version: "HTTP/1.1", statusCode: 200, reasonPhrase: "OK", headers: [
                .init(name: "Content-Length", value: "1"),
            ])),
            .complete,
        ])
        XCTAssertThrowsError(try head.receive(Data("x".utf8))) {
            XCTAssertEqual($0 as? BoundedHTTP1Error, .forbiddenResponseBody)
        }
        try assertParseError("HTTP/1.1 204 No Content\r\nTransfer-Encoding: chunked\r\n\r\n", .forbiddenResponseBody)

        let limits = try BoundedHTTP1Limits(maximumBodyBytes: 3, maximumDeliveryBytes: 2)
        var fixed = try BoundedHTTP1ResponseParser(requestMethod: "GET", limits: limits)
        XCTAssertThrowsError(try fixed.receive(Data("HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\n".utf8))) {
            XCTAssertEqual($0 as? BoundedHTTP1Error, .bodyTooLarge(limit: 3))
        }
        var eof = try BoundedHTTP1ResponseParser(requestMethod: "GET", limits: limits)
        _ = try eof.receive(Data("HTTP/1.1 200 OK\r\n\r\nabc".utf8))
        XCTAssertThrowsError(try eof.receive(Data("d".utf8))) {
            XCTAssertEqual($0 as? BoundedHTTP1Error, .bodyTooLarge(limit: 3))
        }
    }

    func testRejectsMalformedChunksPrematureEOFAndBytesAfterCompletion() throws {
        try assertParseError("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4;x=y\r\n", .invalidChunk)
        try assertParseError(
            "HTTP/1.1 200 OK\r\nContent-Length: 999999999999999999999999999999999\r\n\r\n",
            .invalidContentLength
        )
        var parser = try BoundedHTTP1ResponseParser(requestMethod: "GET")
        _ = try parser.receive(Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nx".utf8))
        XCTAssertThrowsError(try parser.finishEOF()) {
            XCTAssertEqual($0 as? BoundedHTTP1Error, .unexpectedEndOfStream)
        }

        var complete = try BoundedHTTP1ResponseParser(requestMethod: "GET")
        _ = try complete.receive(Data("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n".utf8))
        XCTAssertThrowsError(try complete.receive(Data("x".utf8))) {
            XCTAssertEqual($0 as? BoundedHTTP1Error, .unexpectedDataAfterCompletion)
        }
    }

    func testErrorsAreRedacted() {
        XCTAssertEqual(String(describing: BoundedHTTP1Error.invalidHeader), "BoundedHTTP1Error(<redacted>)")
        XCTAssertEqual(String(reflecting: BoundedHTTP1Error.invalidChunk), "BoundedHTTP1Error(<redacted>)")
    }

    private func assertParseError(
        _ wire: String,
        _ expected: BoundedHTTP1Error,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var parser = try BoundedHTTP1ResponseParser(requestMethod: "GET")
        XCTAssertThrowsError(try parser.receive(Data(wire.utf8)), file: file, line: line) {
            XCTAssertEqual($0 as? BoundedHTTP1Error, expected, file: file, line: line)
        }
    }
}

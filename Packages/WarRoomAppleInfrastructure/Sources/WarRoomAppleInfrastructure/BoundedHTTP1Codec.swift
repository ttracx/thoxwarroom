import Foundation

/// Resource limits for the deliberately small HTTP/1.1 codec used by private transports.
public struct BoundedHTTP1Limits: Equatable, Sendable {
    public let maximumHeaderBytes: Int
    public let maximumHeaderCount: Int
    public let maximumLineBytes: Int
    public let maximumBodyBytes: Int
    public let maximumDeliveryBytes: Int

    public init(
        maximumHeaderBytes: Int = 32 * 1_024,
        maximumHeaderCount: Int = 64,
        maximumLineBytes: Int = 8 * 1_024,
        maximumBodyBytes: Int = 16 * 1_024 * 1_024,
        maximumDeliveryBytes: Int = 16 * 1_024
    ) throws {
        guard maximumHeaderBytes > 0,
              maximumHeaderCount > 0,
              maximumLineBytes > 0,
              maximumLineBytes <= maximumHeaderBytes,
              maximumBodyBytes >= 0,
              maximumDeliveryBytes > 0,
              maximumDeliveryBytes <= max(maximumBodyBytes, 1)
        else {
            throw BoundedHTTP1Error.invalidLimits
        }
        self.maximumHeaderBytes = maximumHeaderBytes
        self.maximumHeaderCount = maximumHeaderCount
        self.maximumLineBytes = maximumLineBytes
        self.maximumBodyBytes = maximumBodyBytes
        self.maximumDeliveryBytes = maximumDeliveryBytes
    }

    public static let secureDefault = BoundedHTTP1Limits(
        validatedMaximumHeaderBytes: 32 * 1_024,
        maximumHeaderCount: 64,
        maximumLineBytes: 8 * 1_024,
        maximumBodyBytes: 16 * 1_024 * 1_024,
        maximumDeliveryBytes: 16 * 1_024
    )

    private init(
        validatedMaximumHeaderBytes: Int,
        maximumHeaderCount: Int,
        maximumLineBytes: Int,
        maximumBodyBytes: Int,
        maximumDeliveryBytes: Int
    ) {
        self.maximumHeaderBytes = validatedMaximumHeaderBytes
        self.maximumHeaderCount = maximumHeaderCount
        self.maximumLineBytes = maximumLineBytes
        self.maximumBodyBytes = maximumBodyBytes
        self.maximumDeliveryBytes = maximumDeliveryBytes
    }
}

/// Errors intentionally expose only a category and numeric limits, never wire bytes.
public enum BoundedHTTP1Error: Error, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    case invalidLimits
    case invalidMethod
    case invalidRequestTarget
    case invalidHeader
    case forbiddenRequestFraming
    case requestTooLarge(limit: Int)
    case malformedLineEnding
    case lineTooLong(limit: Int)
    case headersTooLarge(limit: Int)
    case tooManyHeaders(limit: Int)
    case invalidStatusLine
    case unsupportedUpgrade
    case ambiguousFraming
    case invalidContentLength
    case unsupportedTransferEncoding
    case forbiddenResponseBody
    case invalidChunk
    case trailersNotAllowed
    case bodyTooLarge(limit: Int)
    case unexpectedEndOfStream
    case unexpectedDataAfterCompletion

    public var description: String { "BoundedHTTP1Error(<redacted>)" }
    public var debugDescription: String { description }
}

public struct BoundedHTTP1Header: Equatable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct BoundedHTTP1Request: Equatable, Sendable {
    public let method: String
    public let target: String
    public let headers: [BoundedHTTP1Header]
    public let body: Data

    public init(
        method: String,
        target: String,
        headers: [BoundedHTTP1Header] = [],
        body: Data = Data()
    ) {
        self.method = method
        self.target = target
        self.headers = headers
        self.body = body
    }
}

public enum BoundedHTTP1RequestSerializer {
    /// Serializes one origin-form HTTP/1.1 request after rejecting injection and
    /// request-smuggling primitives. The caller remains responsible for a Host header.
    public static func serialize(
        _ request: BoundedHTTP1Request,
        limits: BoundedHTTP1Limits = .secureDefault
    ) throws -> Data {
        guard isToken(request.method), !request.method.isEmpty else {
            throw BoundedHTTP1Error.invalidMethod
        }
        guard isValidOriginFormTarget(request.target) else {
            throw BoundedHTTP1Error.invalidRequestTarget
        }
        guard request.body.count <= limits.maximumBodyBytes else {
            throw BoundedHTTP1Error.requestTooLarge(limit: limits.maximumBodyBytes)
        }
        guard request.headers.count <= limits.maximumHeaderCount else {
            throw BoundedHTTP1Error.tooManyHeaders(limit: limits.maximumHeaderCount)
        }

        let requestLine = Data("\(request.method) \(request.target) HTTP/1.1\r\n".utf8)
        guard requestLine.count - 2 <= limits.maximumLineBytes else {
            throw BoundedHTTP1Error.lineTooLong(limit: limits.maximumLineBytes)
        }
        var output = requestLine
        var contentLengths: [Int] = []
        var hasTransferEncoding = false
        for header in request.headers {
            guard isToken(header.name), isValidHeaderValue(header.value) else {
                throw BoundedHTTP1Error.invalidHeader
            }
            switch header.name.lowercased() {
            case "content-length":
                guard let values = parseContentLengthValues(header.value) else {
                    throw BoundedHTTP1Error.invalidContentLength
                }
                contentLengths.append(contentsOf: values)
            case "transfer-encoding":
                hasTransferEncoding = true
            default:
                break
            }
            let fieldLine = Data("\(header.name): \(header.value)\r\n".utf8)
            guard fieldLine.count - 2 <= limits.maximumLineBytes else {
                throw BoundedHTTP1Error.lineTooLong(limit: limits.maximumLineBytes)
            }
            output.append(fieldLine)
        }
        guard !hasTransferEncoding else {
            throw BoundedHTTP1Error.forbiddenRequestFraming
        }
        if let first = contentLengths.first,
           contentLengths.contains(where: { $0 != first }) || first != request.body.count {
            throw BoundedHTTP1Error.ambiguousFraming
        }
        if contentLengths.isEmpty, !request.body.isEmpty {
            guard request.headers.count < limits.maximumHeaderCount else {
                throw BoundedHTTP1Error.tooManyHeaders(limit: limits.maximumHeaderCount)
            }
            output.append(Data("Content-Length: \(request.body.count)\r\n".utf8))
        }
        output.append(Data("\r\n".utf8))
        guard output.count <= limits.maximumHeaderBytes else {
            throw BoundedHTTP1Error.headersTooLarge(limit: limits.maximumHeaderBytes)
        }
        output.append(request.body)
        return output
    }
}

public struct BoundedHTTP1ResponseHead: Equatable, Sendable {
    public let version: String
    public let statusCode: Int
    public let reasonPhrase: String
    public let headers: [BoundedHTTP1Header]

    public init(version: String, statusCode: Int, reasonPhrase: String, headers: [BoundedHTTP1Header]) {
        self.version = version
        self.statusCode = statusCode
        self.reasonPhrase = reasonPhrase
        self.headers = headers
    }
}

public enum BoundedHTTP1ResponseEvent: Equatable, Sendable {
    case informational(BoundedHTTP1ResponseHead)
    case head(BoundedHTTP1ResponseHead)
    case body(Data)
    case complete
}

/// Incremental single-response parser with bounded headers, total body size,
/// and body-event delivery. It does not support pipelining or upgrades.
public struct BoundedHTTP1ResponseParser: Sendable {
    private enum State: Sendable {
        case status
        case headers
        case fixed(remaining: Int)
        case chunkSize
        case chunkData(remaining: Int)
        case chunkDataCRLF
        case finalChunk
        case eof
        case complete
    }

    private let requestMethod: String
    private let limits: BoundedHTTP1Limits
    private var state: State = .status
    private var buffer = Data()
    private var headerBytes = 0
    private var headers: [BoundedHTTP1Header] = []
    private var version = ""
    private var statusCode = 0
    private var reasonPhrase = ""
    private var deliveredBodyBytes = 0
    private var responseBodyForbidden = false

    public init(requestMethod: String, limits: BoundedHTTP1Limits = .secureDefault) throws {
        guard isToken(requestMethod), !requestMethod.isEmpty else {
            throw BoundedHTTP1Error.invalidMethod
        }
        self.requestMethod = requestMethod.uppercased()
        self.limits = limits
    }

    public mutating func receive(_ bytes: Data) throws -> [BoundedHTTP1ResponseEvent] {
        guard !bytes.isEmpty else { return [] }
        var events: [BoundedHTTP1ResponseEvent] = []
        var offset = 0
        let ingressChunkBytes = max(limits.maximumLineBytes, limits.maximumDeliveryBytes)

        // A caller can supply an arbitrarily large Data value even though the
        // production adapters use bounded Network.framework receives. Feed that
        // value through the parser in policy-bounded slices so `buffer` never
        // transiently duplicates the entire untrusted input before limits run.
        while offset < bytes.count {
            guard !isComplete else {
                throw responseBodyForbidden
                    ? BoundedHTTP1Error.forbiddenResponseBody
                    : BoundedHTTP1Error.unexpectedDataAfterCompletion
            }
            let count = min(ingressChunkBytes, bytes.count - offset)
            buffer.append(bytes[offset..<(offset + count)])
            events += try process(endOfStream: false)
            offset += count
        }
        return events
    }

    public mutating func finishEOF() throws -> [BoundedHTTP1ResponseEvent] {
        if isComplete {
            guard buffer.isEmpty else { throw BoundedHTTP1Error.unexpectedDataAfterCompletion }
            return []
        }
        let events = try process(endOfStream: true)
        guard isComplete else { throw BoundedHTTP1Error.unexpectedEndOfStream }
        return events
    }

    public var isComplete: Bool {
        if case .complete = state { return true }
        return false
    }

    private mutating func process(endOfStream: Bool) throws -> [BoundedHTTP1ResponseEvent] {
        var events: [BoundedHTTP1ResponseEvent] = []
        processing: while true {
            switch state {
            case .status:
                guard let line = try takeLine(countingAsHeader: true) else { break processing }
                try parseStatusLine(line)
                state = .headers

            case .headers:
                guard let line = try takeLine(countingAsHeader: true) else { break processing }
                if line.isEmpty {
                    let head = BoundedHTTP1ResponseHead(
                        version: version,
                        statusCode: statusCode,
                        reasonPhrase: reasonPhrase,
                        headers: headers
                    )
                    if (100..<200).contains(statusCode) {
                        guard statusCode != 101 else { throw BoundedHTTP1Error.unsupportedUpgrade }
                        try ensureBodyForbiddenFraming()
                        events.append(.informational(head))
                        resetHead()
                        state = .status
                    } else {
                        events.append(.head(head))
                        state = try determineBodyState()
                        if case .complete = state { events.append(.complete) }
                    }
                } else {
                    try parseHeaderLine(line)
                }

            case let .fixed(remaining):
                if remaining == 0 {
                    state = .complete
                    events.append(.complete)
                    continue
                }
                guard !buffer.isEmpty else { break processing }
                let count = min(remaining, min(buffer.count, limits.maximumDeliveryBytes))
                try deliver(count: count, into: &events)
                state = .fixed(remaining: remaining - count)

            case .chunkSize:
                guard let line = try takeLine(countingAsHeader: false) else { break processing }
                guard !line.isEmpty, !line.contains(0x3B),
                      let text = String(bytes: line, encoding: .ascii),
                      text.allSatisfy({ $0.isHexDigit }),
                      let size = Int(text, radix: 16)
                else { throw BoundedHTTP1Error.invalidChunk }
                guard size <= limits.maximumBodyBytes - deliveredBodyBytes else {
                    throw BoundedHTTP1Error.bodyTooLarge(limit: limits.maximumBodyBytes)
                }
                state = size == 0 ? .finalChunk : .chunkData(remaining: size)

            case let .chunkData(remaining):
                guard !buffer.isEmpty else { break processing }
                let count = min(remaining, min(buffer.count, limits.maximumDeliveryBytes))
                try deliver(count: count, into: &events)
                let next = remaining - count
                state = next == 0 ? .chunkDataCRLF : .chunkData(remaining: next)

            case .chunkDataCRLF:
                guard buffer.count >= 2 else { break processing }
                guard buffer[buffer.startIndex] == 0x0D,
                      buffer[buffer.index(after: buffer.startIndex)] == 0x0A
                else { throw BoundedHTTP1Error.malformedLineEnding }
                buffer.removeFirst(2)
                state = .chunkSize

            case .finalChunk:
                guard let line = try takeLine(countingAsHeader: false) else { break processing }
                guard line.isEmpty else { throw BoundedHTTP1Error.trailersNotAllowed }
                state = .complete
                events.append(.complete)

            case .eof:
                if !buffer.isEmpty {
                    let count = min(buffer.count, limits.maximumDeliveryBytes)
                    try deliver(count: count, into: &events)
                } else if endOfStream {
                    state = .complete
                    events.append(.complete)
                } else {
                    break processing
                }

            case .complete:
                guard buffer.isEmpty else {
                    throw responseBodyForbidden
                        ? BoundedHTTP1Error.forbiddenResponseBody
                        : BoundedHTTP1Error.unexpectedDataAfterCompletion
                }
                break processing
            }
        }

        if endOfStream {
            switch state {
            case .eof where buffer.isEmpty:
                state = .complete
                events.append(.complete)
            case .complete:
                break
            default:
                throw BoundedHTTP1Error.unexpectedEndOfStream
            }
        }
        return events
    }

    private mutating func takeLine(countingAsHeader: Bool) throws -> [UInt8]? {
        if let lf = buffer.firstIndex(of: 0x0A) {
            guard lf > buffer.startIndex else { throw BoundedHTTP1Error.malformedLineEnding }
            let cr = buffer.index(before: lf)
            guard buffer[cr] == 0x0D else { throw BoundedHTTP1Error.malformedLineEnding }
            let count = buffer.distance(from: buffer.startIndex, to: cr)
            guard !buffer.prefix(count).contains(0x0D) else {
                throw BoundedHTTP1Error.malformedLineEnding
            }
            guard count <= limits.maximumLineBytes else {
                throw BoundedHTTP1Error.lineTooLong(limit: limits.maximumLineBytes)
            }
            let consumed = count + 2
            if countingAsHeader {
                guard headerBytes <= limits.maximumHeaderBytes - consumed else {
                    throw BoundedHTTP1Error.headersTooLarge(limit: limits.maximumHeaderBytes)
                }
                headerBytes += consumed
            }
            let line = Array(buffer.prefix(count))
            buffer.removeFirst(consumed)
            return line
        }

        if let cr = buffer.firstIndex(of: 0x0D), cr != buffer.index(before: buffer.endIndex) {
            throw BoundedHTTP1Error.malformedLineEnding
        }
        guard buffer.count <= limits.maximumLineBytes + 1 else {
            throw BoundedHTTP1Error.lineTooLong(limit: limits.maximumLineBytes)
        }
        if countingAsHeader,
           headerBytes > limits.maximumHeaderBytes - buffer.count {
            throw BoundedHTTP1Error.headersTooLarge(limit: limits.maximumHeaderBytes)
        }
        return nil
    }

    private mutating func parseStatusLine(_ bytes: [UInt8]) throws {
        guard bytes.allSatisfy(isReasonByte),
              let line = String(bytes: bytes, encoding: .ascii),
              line.count >= 12
        else { throw BoundedHTTP1Error.invalidStatusLine }
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2,
              parts[0] == "HTTP/1.1" || parts[0] == "HTTP/1.0",
              parts[1].count == 3,
              parts[1].allSatisfy(\.isNumber),
              let code = Int(parts[1]),
              (100...599).contains(code)
        else { throw BoundedHTTP1Error.invalidStatusLine }
        version = String(parts[0])
        statusCode = code
        reasonPhrase = parts.count == 3 ? String(parts[2]) : ""
    }

    private mutating func parseHeaderLine(_ bytes: [UInt8]) throws {
        guard bytes.first != 0x20, bytes.first != 0x09,
              let colon = bytes.firstIndex(of: 0x3A), colon > 0
        else { throw BoundedHTTP1Error.invalidHeader }
        let nameBytes = Array(bytes[..<colon])
        var valueBytes = Array(bytes[(colon + 1)...])
        while valueBytes.first == 0x20 || valueBytes.first == 0x09 { valueBytes.removeFirst() }
        while valueBytes.last == 0x20 || valueBytes.last == 0x09 { valueBytes.removeLast() }
        guard let name = String(bytes: nameBytes, encoding: .ascii), isToken(name),
              let value = String(bytes: valueBytes, encoding: .ascii), isValidHeaderValue(value)
        else { throw BoundedHTTP1Error.invalidHeader }
        guard headers.count < limits.maximumHeaderCount else {
            throw BoundedHTTP1Error.tooManyHeaders(limit: limits.maximumHeaderCount)
        }
        headers.append(BoundedHTTP1Header(name: name, value: value))
    }

    private mutating func determineBodyState() throws -> State {
        let contentLengths = try parsedContentLengths()
        let transferEncodings = headers
            .filter { $0.name.caseInsensitiveCompare("transfer-encoding") == .orderedSame }
            .flatMap { $0.value.split(separator: ",", omittingEmptySubsequences: false) }
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        if !transferEncodings.isEmpty, !contentLengths.isEmpty {
            throw BoundedHTTP1Error.ambiguousFraming
        }
        if requestMethod == "CONNECT", (200..<300).contains(statusCode) {
            throw BoundedHTTP1Error.unsupportedUpgrade
        }
        let bodyForbidden = requestMethod == "HEAD" || statusCode == 204 || statusCode == 304
        if bodyForbidden {
            // Content-Length is meaningful metadata on HEAD and 304. RFC 9112
            // forbids Content-Length and Transfer-Encoding on 204 responses.
            if statusCode == 204, !contentLengths.isEmpty || !transferEncodings.isEmpty {
                throw BoundedHTTP1Error.forbiddenResponseBody
            }
            responseBodyForbidden = true
            return .complete
        }
        if !transferEncodings.isEmpty {
            guard transferEncodings == ["chunked"] else {
                throw BoundedHTTP1Error.unsupportedTransferEncoding
            }
            return .chunkSize
        }
        if let length = contentLengths.first {
            guard length <= limits.maximumBodyBytes else {
                throw BoundedHTTP1Error.bodyTooLarge(limit: limits.maximumBodyBytes)
            }
            return length == 0 ? .complete : .fixed(remaining: length)
        }
        return .eof
    }

    private func parsedContentLengths() throws -> [Int] {
        var values: [Int] = []
        for header in headers where header.name.caseInsensitiveCompare("content-length") == .orderedSame {
            guard let parsed = parseContentLengthValues(header.value) else {
                throw BoundedHTTP1Error.invalidContentLength
            }
            values.append(contentsOf: parsed)
        }
        if let first = values.first, values.contains(where: { $0 != first }) {
            throw BoundedHTTP1Error.ambiguousFraming
        }
        return values
    }

    private func ensureBodyForbiddenFraming() throws {
        if headers.contains(where: { $0.name.caseInsensitiveCompare("transfer-encoding") == .orderedSame }) {
            throw BoundedHTTP1Error.forbiddenResponseBody
        }
        // RFC 9112 forbids Content-Length on every 1xx response, including zero.
        guard try parsedContentLengths().isEmpty else {
            throw BoundedHTTP1Error.forbiddenResponseBody
        }
    }

    private mutating func deliver(count: Int, into events: inout [BoundedHTTP1ResponseEvent]) throws {
        guard count > 0,
              deliveredBodyBytes <= limits.maximumBodyBytes - count
        else { throw BoundedHTTP1Error.bodyTooLarge(limit: limits.maximumBodyBytes) }
        let chunk = Data(buffer.prefix(count))
        buffer.removeFirst(count)
        deliveredBodyBytes += count
        events.append(.body(chunk))
    }

    private mutating func resetHead() {
        headerBytes = 0
        headers.removeAll(keepingCapacity: true)
        version = ""
        statusCode = 0
        reasonPhrase = ""
    }
}

private func isToken(_ value: String) -> Bool {
    !value.isEmpty && !value.utf8.contains { byte in
        !(byte == 0x21 || (0x23...0x27).contains(byte) || byte == 0x2A || byte == 0x2B ||
          byte == 0x2D || byte == 0x2E || (0x30...0x39).contains(byte) ||
          (0x41...0x5A).contains(byte) || (0x5E...0x7A).contains(byte) || byte == 0x7C || byte == 0x7E)
    }
}

private func isValidOriginFormTarget(_ value: String) -> Bool {
    guard value.utf8.first == 0x2F, !value.contains("#"), !value.hasPrefix("//") else { return false }
    let bytes = Array(value.utf8)
    var index = 0
    while index < bytes.count {
        let byte = bytes[index]
        if byte == 0x25 { // percent-encoded octet
            guard index + 2 < bytes.count,
                  isASCIIHexDigit(bytes[index + 1]),
                  isASCIIHexDigit(bytes[index + 2])
            else { return false }
            index += 3
            continue
        }
        guard isOriginFormByte(byte) else { return false }
        index += 1
    }
    return true
}

private func isValidHeaderValue(_ value: String) -> Bool {
    value.utf8.allSatisfy { $0 == 0x09 || (0x20...0x7E).contains($0) }
}

private func isReasonByte(_ byte: UInt8) -> Bool {
    byte == 0x09 || (0x20...0x7E).contains(byte)
}

private func isASCIIHexDigit(_ byte: UInt8) -> Bool {
    (0x30...0x39).contains(byte) || (0x41...0x46).contains(byte) || (0x61...0x66).contains(byte)
}

private func isOriginFormByte(_ byte: UInt8) -> Bool {
    (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte) ||
        (0x30...0x39).contains(byte) ||
        [0x2D, 0x2E, 0x5F, 0x7E, // unreserved
         0x21, 0x24, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x3B, 0x3D, // sub-delims
         0x3A, 0x40, 0x2F, 0x3F].contains(byte) // pchar plus path/query delimiters
}

private func parseContentLengthValues(_ value: String) -> [Int]? {
    let parts = value.split(separator: ",", omittingEmptySubsequences: false)
    guard !parts.isEmpty else { return nil }
    var values: [Int] = []
    for part in parts {
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              trimmed.utf8.allSatisfy({ (0x30...0x39).contains($0) }),
              let parsed = Int(trimmed)
        else { return nil }
        values.append(parsed)
    }
    return values
}

import Foundation

public struct HermesEventMetadata: Equatable, Sendable {
    public let runID: HermesRunID?
    public let timestamp: String?

    public init(runID: HermesRunID?, timestamp: String?) {
        self.runID = runID
        self.timestamp = timestamp
    }
}

public struct HermesMessageDeltaEvent: Equatable, Sendable {
    public let metadata: HermesEventMetadata
    public let delta: String
}

public struct HermesToolEvent: Equatable, Sendable {
    public let metadata: HermesEventMetadata
    public let toolName: String?
}

public struct HermesApprovalRequestEvent: Equatable, Sendable {
    public let metadata: HermesEventMetadata
    public let choices: [HermesApprovalChoice]
}

public struct HermesApprovalRespondedEvent: Equatable, Sendable {
    public let metadata: HermesEventMetadata
    public let choice: HermesApprovalChoice?
}

public struct HermesUnknownEvent: Equatable, Sendable {
    /// A bounded safe event name, or `<redacted>` when the wire name is unsafe.
    public let auditName: String
    /// Unknown payload bytes are always discarded.
    public let payloadWasDiscarded: Bool
}

public enum HermesRunEvent: Equatable, Sendable {
    case messageDelta(HermesMessageDeltaEvent)
    case toolStarted(HermesToolEvent)
    case toolCompleted(HermesToolEvent)
    case reasoningAvailable(HermesEventMetadata)
    case approvalRequest(HermesApprovalRequestEvent)
    case approvalResponded(HermesApprovalRespondedEvent)
    case runCompleted(HermesEventMetadata)
    case runFailed(HermesEventMetadata)
    case runCancelled(HermesEventMetadata)
    case unknown(HermesUnknownEvent)
}

public extension HermesRunEvent {
    var runID: HermesRunID? {
        switch self {
        case .messageDelta(let event): event.metadata.runID
        case .toolStarted(let event), .toolCompleted(let event): event.metadata.runID
        case .reasoningAvailable(let metadata), .runCompleted(let metadata),
             .runFailed(let metadata), .runCancelled(let metadata): metadata.runID
        case .approvalRequest(let event): event.metadata.runID
        case .approvalResponded(let event): event.metadata.runID
        case .unknown: nil
        }
    }
}

public enum HermesSSEError: Error, Equatable, Sendable {
    case bufferLimitExceeded
    case eventLimitExceeded
    case invalidUTF8
    case missingEventName
    case malformedJSON
    case invalidRunID
    case invalidApprovalChoices
    case missingMessageDelta
}

public struct HermesSSEParser: Sendable {
    private static let hardMaximumBytes = 64 * 1_024 * 1_024

    public let maximumBufferedBytes: Int
    public let maximumEventBytes: Int
    private var buffer = Data()

    public init() {
        self.maximumBufferedBytes = 1_048_576
        self.maximumEventBytes = 262_144
    }

    public init(maximumBufferedBytes: Int, maximumEventBytes: Int) throws {
        guard (1...Self.hardMaximumBytes).contains(maximumBufferedBytes),
              (1...maximumBufferedBytes).contains(maximumEventBytes) else {
            throw HermesLimitError.invalidSSELimits
        }
        self.maximumBufferedBytes = maximumBufferedBytes
        self.maximumEventBytes = maximumEventBytes
    }

    public mutating func append(_ data: Data) throws -> [HermesRunEvent] {
        try Task.checkCancellation()
        guard data.count <= maximumBufferedBytes,
              buffer.count <= maximumBufferedBytes - data.count else {
            buffer.removeAll(keepingCapacity: false)
            throw HermesSSEError.bufferLimitExceeded
        }
        buffer.append(data)

        var events: [HermesRunEvent] = []
        while let boundary = recordBoundary(in: buffer) {
            let record = buffer.prefix(boundary.recordEnd)
            buffer.removeSubrange(0..<boundary.nextRecordStart)
            guard record.count <= maximumEventBytes else {
                throw HermesSSEError.eventLimitExceeded
            }
            if let event = try parseRecord(Data(record)) {
                events.append(event)
            }
            try Task.checkCancellation()
        }
        return events
    }

    public mutating func finish() throws -> [HermesRunEvent] {
        try Task.checkCancellation()
        guard !buffer.isEmpty else { return [] }
        let final = buffer
        buffer.removeAll(keepingCapacity: false)
        guard final.count <= maximumEventBytes else { throw HermesSSEError.eventLimitExceeded }
        return try parseRecord(final).map { [$0] } ?? []
    }

    private func parseRecord(_ record: Data) throws -> HermesRunEvent? {
        guard let text = String(data: record, encoding: .utf8) else {
            throw HermesSSEError.invalidUTF8
        }
        let dataLines = text
            .split(omittingEmptySubsequences: false, whereSeparator: \Character.isNewline)
            .compactMap { line -> String? in
                if line.hasPrefix(":") { return nil }
                guard line == "data" || line.hasPrefix("data:") else { return nil }
                let value = line.dropFirst(5)
                return value.first == " " ? String(value.dropFirst()) : String(value)
            }
        guard !dataLines.isEmpty else { return nil }
        let payload = Data(dataLines.joined(separator: "\n").utf8)
        let wire: WireEvent
        do { wire = try JSONDecoder().decode(WireEvent.self, from: payload) }
        catch { throw HermesSSEError.malformedJSON }
        return try wire.event()
    }

    private func recordBoundary(in data: Data) -> (recordEnd: Int, nextRecordStart: Int)? {
        let bytes = [UInt8](data)
        var index = 0
        while index + 1 < bytes.count {
            if bytes[index] == 10 && bytes[index + 1] == 10 {
                return (index, index + 2)
            }
            if index + 3 < bytes.count,
               bytes[index] == 13, bytes[index + 1] == 10,
               bytes[index + 2] == 13, bytes[index + 3] == 10 {
                return (index, index + 4)
            }
            index += 1
        }
        return nil
    }
}

private struct WireEvent: Decodable {
    struct Payload: Decodable {
        let delta: String?
        let toolName: String?
        let choices: [String]?
        let choice: String?

        enum CodingKeys: String, CodingKey {
            case delta, choices, choice
            case toolName = "tool_name"
        }
    }

    let eventName: String?
    let type: String?
    let runIDValue: String?
    let timestamp: String?
    let delta: String?
    let toolName: String?
    let choices: [String]?
    let choice: String?
    let payload: Payload?

    enum CodingKeys: String, CodingKey {
        case type, timestamp, delta, choices, choice, payload
        case eventName = "event"
        case runIDValue = "run_id"
        case toolName = "tool_name"
    }

    func event() throws -> HermesRunEvent {
        guard let name = eventName ?? type, !name.isEmpty else {
            throw HermesSSEError.missingEventName
        }
        let runID: HermesRunID?
        if let runIDValue {
            guard let value = HermesRunID(rawValue: runIDValue) else { throw HermesSSEError.invalidRunID }
            runID = value
        } else {
            runID = nil
        }
        let metadata = HermesEventMetadata(runID: runID, timestamp: safeTimestamp(timestamp))

        switch name {
        case "message.delta":
            guard let value = delta ?? payload?.delta else { throw HermesSSEError.missingMessageDelta }
            return .messageDelta(HermesMessageDeltaEvent(metadata: metadata, delta: value))
        case "tool.started":
            return .toolStarted(HermesToolEvent(
                metadata: metadata,
                toolName: bounded(toolName ?? payload?.toolName, maximum: 128)
            ))
        case "tool.completed":
            return .toolCompleted(HermesToolEvent(
                metadata: metadata,
                toolName: bounded(toolName ?? payload?.toolName, maximum: 128)
            ))
        case "reasoning.available": return .reasoningAvailable(metadata)
        case "approval.request":
            guard let runID else { throw HermesSSEError.invalidRunID }
            let rawChoices = choices ?? payload?.choices ?? []
            let parsedChoices = rawChoices.compactMap(HermesApprovalChoice.init(rawValue:))
            guard parsedChoices.count == rawChoices.count,
                  rawChoices.count == HermesApprovalChoice.allCases.count,
                  !parsedChoices.isEmpty,
                  Set(parsedChoices) == Set(HermesApprovalChoice.allCases) else {
                throw HermesSSEError.invalidApprovalChoices
            }
            return .approvalRequest(HermesApprovalRequestEvent(
                metadata: HermesEventMetadata(runID: runID, timestamp: metadata.timestamp),
                choices: parsedChoices
            ))
        case "approval.responded":
            let rawChoice = choice ?? payload?.choice
            let parsedChoice = rawChoice.flatMap(HermesApprovalChoice.init(rawValue:))
            if rawChoice != nil, parsedChoice == nil { throw HermesSSEError.invalidApprovalChoices }
            return .approvalResponded(HermesApprovalRespondedEvent(metadata: metadata, choice: parsedChoice))
        case "run.completed": return .runCompleted(metadata)
        case "run.failed": return .runFailed(metadata)
        case "run.cancelled": return .runCancelled(metadata)
        default:
            return .unknown(HermesUnknownEvent(
                auditName: safeAuditName(name),
                payloadWasDiscarded: true
            ))
        }
    }

    private func bounded(_ value: String?, maximum: Int) -> String? {
        value.map { String($0.prefix(maximum)) }
    }

    private func safeTimestamp(_ value: String?) -> String? {
        guard let value, value.count <= 64 else { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789TZtz+-:.")
        return value.unicodeScalars.allSatisfy(allowed.contains) ? value : nil
    }

    private func safeAuditName(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard value.unicodeScalars.allSatisfy(allowed.contains) else { return "<redacted>" }
        return String(value.prefix(64))
    }
}

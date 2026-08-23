import Foundation

public struct HermesRunID: RawRepresentable, Hashable, Codable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty,
              rawValue.utf8.count <= 256,
              !rawValue.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return nil
        }
        self.rawValue = rawValue
    }

    public var description: String { "<opaque-run-id>" }
    public var debugDescription: String { "HermesRunID(<opaque>)" }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let runID = HermesRunID(rawValue: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid opaque run ID")
        }
        self = runID
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct HermesMessage: Equatable, Codable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public enum HermesRunInput: Equatable, Codable, Sendable {
    case text(String)
    case messages([HermesMessage])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else {
            self = .messages(try container.decode([HermesMessage].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .messages(let messages): try container.encode(messages)
        }
    }
}

public struct HermesRunSubmitRequest: Equatable, Codable, Sendable {
    public let input: HermesRunInput
    public let instructions: String?
    public let previousResponseID: String?
    public let conversationHistory: [HermesMessage]?
    public let sessionID: String?
    public let model: String?

    public init(
        input: HermesRunInput,
        instructions: String? = nil,
        previousResponseID: String? = nil,
        conversationHistory: [HermesMessage]? = nil,
        sessionID: String? = nil,
        model: String? = nil
    ) {
        self.input = input
        self.instructions = instructions
        self.previousResponseID = previousResponseID
        self.conversationHistory = conversationHistory
        self.sessionID = sessionID
        self.model = model
    }

    enum CodingKeys: String, CodingKey {
        case input, instructions, model
        case previousResponseID = "previous_response_id"
        case conversationHistory = "conversation_history"
        case sessionID = "session_id"
    }
}

public struct HermesRunSubmitResponse: Equatable, Codable, Sendable {
    public let runID: HermesRunID
    public let status: HermesRunStatus

    public init(runID: HermesRunID, status: HermesRunStatus) {
        self.runID = runID
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case status
    }
}

public struct HermesRunStatus: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public static let started = HermesRunStatus(rawValue: "started")
    public static let running = HermesRunStatus(rawValue: "running")
    public static let completed = HermesRunStatus(rawValue: "completed")
    public static let failed = HermesRunStatus(rawValue: "failed")
    public static let cancelled = HermesRunStatus(rawValue: "cancelled")
}

public struct HermesRunStatusResponse: Equatable, Codable, Sendable {
    public let runID: HermesRunID
    public let status: HermesRunStatus

    public init(runID: HermesRunID, status: HermesRunStatus) {
        self.runID = runID
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case status
    }
}

public enum HermesApprovalChoice: String, CaseIterable, Codable, Sendable {
    case once
    case session
    case always
    case deny
}

public struct HermesApprovalRequest: Equatable, Codable, Sendable {
    public let choice: HermesApprovalChoice
    public let resolveAll: Bool

    public init(choice: HermesApprovalChoice, resolveAll: Bool = false) {
        self.choice = choice
        self.resolveAll = resolveAll
    }

    enum CodingKeys: String, CodingKey {
        case choice
        case resolveAll = "resolve_all"
    }
}

public struct HermesApprovalResponse: Equatable, Codable, Sendable {
    public let object: String
    public let runID: HermesRunID
    public let choice: HermesApprovalChoice
    public let resolved: Int

    public init(object: String, runID: HermesRunID, choice: HermesApprovalChoice, resolved: Int) {
        self.object = object
        self.runID = runID
        self.choice = choice
        self.resolved = resolved
    }

    enum CodingKeys: String, CodingKey {
        case object, choice, resolved
        case runID = "run_id"
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let object = try values.decode(String.self, forKey: .object)
        let resolved = try values.decode(Int.self, forKey: .resolved)
        guard object == "hermes.run.approval_response", resolved >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .object,
                in: values,
                debugDescription: "Invalid approval response"
            )
        }
        self.object = object
        self.runID = try values.decode(HermesRunID.self, forKey: .runID)
        self.choice = try values.decode(HermesApprovalChoice.self, forKey: .choice)
        self.resolved = resolved
    }
}

/// Stop currently has no documented request fields. Encoding this marker
/// produces `{}`; the client sends no body until a live contract is captured.
public struct HermesStopRequest: Equatable, Codable, Sendable {
    public init() {}
}

/// The stop response body is not yet frozen. These source-observed fields are
/// optional so a successful empty response remains representable.
public struct HermesStopResponse: Equatable, Codable, Sendable {
    public let runID: HermesRunID?
    public let status: HermesRunStatus?

    public init(runID: HermesRunID? = nil, status: HermesRunStatus? = nil) {
        self.runID = runID
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case status
    }
}

/// The current contract does not freeze exact capability keys. Typed bounded
/// maps retain advertised booleans and paths without treating unknown fields as authorization.
public struct HermesCapabilitiesResponse: Equatable, Codable, Sendable {
    public let runtimeMode: String?
    public let features: [String: Bool]
    public let endpoints: [String: String]

    public init(
        runtimeMode: String? = nil,
        features: [String: Bool] = [:],
        endpoints: [String: String] = [:]
    ) {
        self.runtimeMode = runtimeMode
        self.features = features
        self.endpoints = endpoints
    }

    enum CodingKeys: String, CodingKey {
        case runtimeMode = "runtime_mode"
        case features, endpoints
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let runtimeMode = try values.decodeIfPresent(String.self, forKey: .runtimeMode)
        let features = try values.decodeIfPresent([String: Bool].self, forKey: .features) ?? [:]
        let endpoints = try values.decodeIfPresent([String: String].self, forKey: .endpoints) ?? [:]
        guard runtimeMode.map({ $0.utf8.count <= 128 }) ?? true,
              features.count <= 256,
              endpoints.count <= 256,
              features.keys.allSatisfy({ $0.utf8.count <= 128 }),
              endpoints.allSatisfy({ $0.key.utf8.count <= 128 && $0.value.utf8.count <= 512 }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .features,
                in: values,
                debugDescription: "Capabilities exceed client bounds"
            )
        }
        self.runtimeMode = runtimeMode
        self.features = features
        self.endpoints = endpoints
    }
}

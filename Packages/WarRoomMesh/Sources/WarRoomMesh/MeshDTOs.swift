import Foundation

/// Validated identity for one private mesh.
public struct MeshID: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    /// Underlying UUID.
    public let rawValue: UUID

    /// Creates an identity from an already validated UUID.
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    /// Parses a canonical UUID string without performing network access.
    public init(validating value: String) throws {
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              let uuid = UUID(uuidString: value),
              uuid.uuidString.lowercased() == value.lowercased() else {
            throw MeshInputError.invalidMeshIdentifier
        }
        rawValue = uuid
    }

    /// Decodes a mesh identity from its canonical UUID string representation.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do {
            try self.init(validating: value)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a canonical mesh UUID"
            )
        }
    }

    /// Encodes a mesh identity as its canonical lowercase UUID string.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(queryValue)
    }

    /// Canonical lowercase value used in query parameters.
    public var queryValue: String {
        rawValue.uuidString.lowercased()
    }
}

/// Validated event page size accepted by the current coordinator contract.
public struct MeshEventLimit: Equatable, Hashable, Sendable {
    /// Page-size value in the closed range `1...500`.
    public let rawValue: Int

    /// Validates the coordinator event limit.
    public init(rawValue: Int) throws {
        guard (1...500).contains(rawValue) else {
            throw MeshInputError.invalidEventLimit(rawValue)
        }
        self.rawValue = rawValue
    }

    /// Current coordinator default used by the native client.
    public static let standard = MeshEventLimit(validatedRawValue: 50)

    private init(validatedRawValue: Int) {
        rawValue = validatedRawValue
    }
}

/// Invalid caller input rejected before transport execution.
public enum MeshInputError: Error, Equatable, Sendable {
    /// A mesh identifier was not a canonical UUID.
    case invalidMeshIdentifier
    /// An event limit fell outside `1...500`.
    case invalidEventLimit(Int)
}

/// Minimal read-only device metadata required by the War Room status surface.
public struct MeshDevice: Decodable, Equatable, Sendable {
    /// Device identity.
    public let id: UUID
    /// Mesh that owns the device.
    public let meshID: MeshID
    /// User-visible device name.
    public let displayName: String
    /// Coordinator platform value.
    public let platform: String
    /// Coordinator role value.
    public let role: String
    /// Last heartbeat timestamp, when available.
    public let lastSeen: Date?

    /// Creates minimal read-only device metadata.
    public init(
        id: UUID,
        meshID: MeshID,
        displayName: String,
        platform: String,
        role: String,
        lastSeen: Date?
    ) {
        self.id = id
        self.meshID = meshID
        self.displayName = displayName
        self.platform = platform
        self.role = role
        self.lastSeen = lastSeen
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case meshID = "mesh_id"
        case displayName = "display_name"
        case platform
        case role
        case lastSeen = "last_seen"
    }
}

/// Read-only device list envelope.
public struct MeshDevicesEnvelope: Decodable, Equatable, Sendable {
    /// Devices visible to the authenticated user within the requested mesh.
    public let data: [MeshDevice]

    /// Creates a device-list envelope.
    public init(data: [MeshDevice]) {
        self.data = data
    }
}

/// One node in a computed mesh topology.
public struct MeshTopologyNode: Decodable, Equatable, Sendable {
    /// Device identity represented by this node.
    public let id: UUID
    /// User-visible node name.
    public let displayName: String
    /// Coordinator role value.
    public let role: String
    /// Coordinator platform value.
    public let platform: String
    /// Last heartbeat timestamp, when available.
    public let lastSeen: Date?

    /// Creates one topology node.
    public init(
        id: UUID,
        displayName: String,
        role: String,
        platform: String,
        lastSeen: Date?
    ) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.platform = platform
        self.lastSeen = lastSeen
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case role
        case platform
        case lastSeen = "last_seen"
    }
}

/// One read-only relationship in a computed mesh topology.
public struct MeshTopologyEdge: Decodable, Equatable, Sendable {
    /// Source node identity.
    public let source: UUID
    /// Target node identity.
    public let target: UUID
    /// Observed round-trip latency, when measured.
    public let roundTripMilliseconds: Double?
    /// Whether the coordinator reports an active tunnel.
    public let tunnelActive: Bool

    /// Creates one topology relationship.
    public init(
        source: UUID,
        target: UUID,
        roundTripMilliseconds: Double?,
        tunnelActive: Bool
    ) {
        self.source = source
        self.target = target
        self.roundTripMilliseconds = roundTripMilliseconds
        self.tunnelActive = tunnelActive
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case target
        case roundTripMilliseconds = "rtt_ms"
        case tunnelActive = "tunnel_active"
    }
}

/// Computed topology for one mesh.
public struct MeshTopology: Decodable, Equatable, Sendable {
    /// Mesh represented by this topology.
    public let meshID: MeshID
    /// Devices in the topology.
    public let nodes: [MeshTopologyNode]
    /// Relationships between topology nodes.
    public let edges: [MeshTopologyEdge]

    /// Creates a computed topology.
    public init(meshID: MeshID, nodes: [MeshTopologyNode], edges: [MeshTopologyEdge]) {
        self.meshID = meshID
        self.nodes = nodes
        self.edges = edges
    }

    private enum CodingKeys: String, CodingKey {
        case meshID = "mesh_id"
        case nodes
        case edges
    }
}

/// One coordinator event used by the local War Room alert projection.
public struct MeshEvent: Decodable, Equatable, Sendable {
    /// Event identity.
    public let id: UUID
    /// Related device identity, when the event is device-scoped.
    public let deviceID: UUID?
    /// Coordinator event-type value.
    public let eventType: String
    /// Coordinator severity value used for local alert projection.
    public let severity: String
    /// Optional operator-readable event message.
    public let message: String?
    /// Coordinator event creation time.
    public let createdAt: Date

    /// Creates one read-only coordinator event.
    public init(
        id: UUID,
        deviceID: UUID?,
        eventType: String,
        severity: String,
        message: String?,
        createdAt: Date
    ) {
        self.id = id
        self.deviceID = deviceID
        self.eventType = eventType
        self.severity = severity
        self.message = message
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case deviceID = "device_id"
        case eventType = "event_type"
        case severity
        case message
        case createdAt = "created_at"
    }
}

/// Read-only event list for one mesh.
public struct MeshEventsEnvelope: Decodable, Equatable, Sendable {
    /// Mesh that owns the event stream.
    public let meshID: MeshID
    /// Server-reported number of returned events.
    public let count: Int
    /// Returned events.
    public let data: [MeshEvent]

    /// Creates an event-list envelope.
    public init(meshID: MeshID, count: Int, data: [MeshEvent]) {
        self.meshID = meshID
        self.count = count
        self.data = data
    }

    private enum CodingKeys: String, CodingKey {
        case meshID = "mesh_id"
        case count
        case data
    }
}

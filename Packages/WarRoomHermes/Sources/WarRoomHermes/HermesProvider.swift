import WarRoomCore

/// Static metadata for the clean-room Hermes API-server integration.
public enum HermesProvider {
    /// Capabilities implemented by the current typed Hermes client surface.
    public static let descriptor = ProviderDescriptor(
        id: ProviderID(rawValue: "hermes-api"),
        displayName: "Hermes Agent",
        capabilities: [.hermesSessions, .scopedApprovals]
    )
}

# Architecture Decisions

## ADR-001: Continue with native SwiftUI and recover behavior, not the Flutter runtime

- **Decision:** Keep the v4.2 SwiftUI/XcodeGen foundation and rebuild the required iOS/macOS vertical slices in Swift.
- **Context:** v4.1 contains broad Flutter functionality, while v4.2 replaced it with a compiling native shell. The requested products are iOS and macOS apps.
- **Options considered:** restore Flutter v4.1; maintain a web wrapper; build native SwiftUI with a shared core.
- **Tradeoffs:** native work takes longer than shipping the wrapper and cannot mechanically reuse Dart UI code, but it gives first-class Apple lifecycle, security, accessibility, extensions, windowing, and release behavior. Historical models/tests remain valuable contract references.
- **Security impact:** reduces plugin supply-chain surface and enables explicit Keychain, trust, entitlement, and data-protection controls.
- **Local-first impact:** native provider and storage abstractions replace the current hard-coded hosted-only destination.
- **Compliance impact:** shared typed use cases and local audit events make security controls testable; this does not itself establish compliance.
- **Final choice:** native SwiftUI plus a shared Swift package and platform adapters.
- **Follow-up:** obtain an owner/legal decision confirming the clean-room MIT path (or choose GPL distribution), freeze independently captured backend contracts, define workspace trust policy, and recreate behavior tests without copying GPL implementation.

## ADR-002: Workspace profiles own all network boundaries

- **Decision:** Replace the hard-coded landing URL with explicit workspace profiles. Local/private profiles are primary; THOX hosted access is optional and visibly labeled.
- **Context:** current v4.2 always loads a public endpoint, which conflicts with THOX.ai's local-first default.
- **Options considered:** global base URL; unrestricted user-entered URL; validated workspace profiles.
- **Tradeoffs:** profiles add onboarding work but allow durable identity, policy, trust, and audit boundaries.
- **Security impact:** schemes, hosts, ports, redirect/callback hosts, and capabilities are validated and allowlisted. Secrets remain in Keychain.
- **Local-first impact:** localhost/LAN/private infrastructure can operate without a hosted control plane.
- **Compliance impact:** data destinations and user consent become explicit and reviewable.
- **Final choice:** validated profiles with no silent fallback to cloud.
- **Follow-up:** define profile schema and migration of existing web cookies.

## ADR-003: High-impact Hermes actions are review-gated

- **Decision:** Separate read-only observation from mutating execution. Tool calls, job changes, file writes, and automation runs require explicit policy evaluation and human approval unless an administrator has created a narrow audited rule.
- **Context:** Hermes is agentic and may affect files, services, or external systems.
- **Options considered:** unrestricted execution; UI confirmation only; policy plus approval plus audit.
- **Tradeoffs:** controlled execution adds latency but provides trustworthy enterprise behavior.
- **Security impact:** least privilege, replay protection, scoped approvals, and safe rendering of untrusted tool output.
- **Local-first impact:** policy and audit remain local/private.
- **Compliance impact:** creates review and evidence primitives without claiming certification.
- **Final choice:** policy, approval, execution, and result are separate events with correlation IDs.
- **Follow-up:** threat-model the approval protocol and build negative/replay tests.

## ADR-004: Validate network identity before transport exists

- **Decision:** `WarRoomCore` represents a provider destination only as a `ValidatedEndpoint` with a verified local-machine, private-network, or hosted boundary.
- **Context:** workspace identity, feature capability, credentials, and egress policy must not collapse into an unrestricted URL string.
- **Options considered:** validate in each UI; let transport classify destinations; construct a validated shared-core value before either layer can use an endpoint.
- **Tradeoffs:** strict defaults require explicit configuration for private HTTP and non-default ports. This adds onboarding decisions but makes weaker transport visible and testable.
- **Security impact:** URL credentials, unapproved schemes and ports, path traversal, query/fragment data, boundary mismatches, insecure hosted HTTP, and hosted access without affirmative authorization are rejected before a transport sees the endpoint.
- **Local-first impact:** loopback and private destinations are first-class; public destinations never become an implicit fallback.
- **Compliance impact:** the declared and detected destination class can be retained in redacted audit events. This is a control primitive, not proof of compliance.
- **Final choice:** a dependency-free Swift package owns validation and transport-neutral seams; concrete network and secret-storage adapters remain outside WR-002.
- **Follow-up:** re-check resolved IP addresses at connection time to prevent DNS rebinding, implement Keychain storage, and add redirect/egress enforcement in the transport adapter.

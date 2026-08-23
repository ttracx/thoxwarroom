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

## ADR-005: Keep Apple credentials and provider transport ephemeral and workspace-scoped

- **Decision:** Store provider credentials as non-synchronizing generic-password Keychain items scoped by workspace UUID, and execute provider requests through a cookie-free/cache-free ephemeral URLSession transport restricted to the validated endpoint origin.
- **Context:** Native Open WebUI and Hermes adapters need a reusable Apple execution layer without placing credentials in profile metadata, logs, cookies, caches, or fixtures.
- **Options considered:** reuse the persistent compatibility WebView session; use a shared default URLSession; create explicit Keychain and scoped transport adapters.
- **Tradeoffs:** the explicit adapters add integration work and cannot yet provide live SSE streaming or DNS-resolution enforcement, but make credential lifetime, redirects, resource bounds, and failures independently testable.
- **Security impact:** Keychain synchronization is disabled, accessibility is `WhenUnlockedThisDeviceOnly`, redirects are exact-origin only, and bearer values are validated immediately before transmission. DNS rebinding remains a known follow-up.
- **Local-first impact:** localhost and private providers use the same explicit transport boundary without a hosted fallback.
- **Compliance impact:** credential storage and egress controls are testable primitives; they do not establish compliance or prove a deployed endpoint is safe.
- **Final choice:** `WarRoomAppleInfrastructure` supplies the concrete Apple adapters while provider packages remain transport-neutral.
- **Follow-up:** add resolved-address enforcement, introduce a streaming seam, and complete real private-endpoint/certificate tests.

## ADR-006: Route native surfaces by explicit provider capability

- **Decision:** Persist an explicit provider descriptor in each workspace profile and route only to native surfaces supported by that descriptor. Open WebUI exposes discovery and model catalog; Hermes exposes credential-gated read-only buffered run review; MeshStack exposes a credential- and canonical-MeshID-gated read-only status dashboard.
- **Context:** A generic provider identifier could route incompatible credentials and endpoints into the wrong client, while advertising unimplemented chat or mutation behavior would create unsafe product claims.
- **Options considered:** one generic provider screen; infer provider from endpoint ports; explicit provider selection plus defensive capability gates.
- **Tradeoffs:** provider-specific endpoint policies and UI increase test cases and require legacy-profile mapping, but prevent endpoint heuristics from becoming authorization decisions.
- **Security impact:** provider secrets remain workspace-scoped; Hermes loads one required credential per status/event snapshot; workspace removal deletes the Keychain item before metadata; no Hermes mutation control is exposed without durable audit and replay controls.
- **Local-first impact:** loopback and private endpoints remain the defaults for every provider, with hosted transfer requiring explicit consent.
- **Compliance impact:** the selected provider, boundary, and advertised capability are reviewable control inputs. No compliance certification is claimed.
- **Final choice:** explicit provider selection, provider-specific validated ports, capability-gated routing, and read-only-first native delivery.
- **Follow-up:** add live private-provider contract evidence, DNS-rebinding defense, encrypted audit persistence, and reviewed approval controls before any Hermes mutation UI.

## ADR-007: Treat Apple privacy declarations as a tested source contract

- **Decision:** Bundle one reviewed `PrivacyInfo.xcprivacy` in both Apple app targets and fail local/release builds when its declarations or platform placement drift.
- **Context:** The current executable stores app-only workspace metadata in `UserDefaults`, stores secrets in the device-only Keychain, has no telemetry or tracking SDK, and sends requests only to operator-configured provider infrastructure.
- **Options considered:** omit the app manifest until App Store validation; maintain untested per-platform manifests; share and validate one source manifest.
- **Tradeoffs:** exact validation intentionally fails whenever declarations change, so new storage, SDKs, telemetry, or developer-operated collection requires an explicit review instead of silently extending the existing claim.
- **Security impact:** tracking is false, tracking domains and developer/SDK collection are empty, and the only current required-reason declaration is app-only UserDefaults reason `CA92.1`. This is a source assertion, not proof of provider behavior.
- **Local-first impact:** the declaration makes the absence of THOX telemetry/collection explicit while preserving user-directed connections to local or private providers.
- **Compliance impact:** reproducible manifest evidence improves reviewability but does not replace privacy policy, App Store Connect answers, legal review, or live data-flow verification.
- **Final choice:** one source manifest plus deterministic validation at source, built-app, archive, IPA, and mounted-DMG boundaries; keep the legacy developer-hosted WebView route disabled while its collection/retention contract is unverified.
- **Follow-up:** re-audit before adding any dependency or data flow; add the public privacy/support metadata and an in-app privacy-policy surface before App Store review.

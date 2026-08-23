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
- **Follow-up:** add resolved-address enforcement and complete real private-endpoint/certificate tests; URLSession streaming now exists for Hermes but has no live-provider or reconnect/cursor evidence.

## ADR-006: Route native surfaces by explicit provider capability

- **Decision:** Persist an explicit provider descriptor in each workspace profile and route only to native surfaces supported by that descriptor. Open WebUI exposes discovery and model catalog; Hermes exposes credential-gated read-only live run review; MeshStack exposes a credential- and canonical-MeshID-gated read-only status dashboard.
- **Context:** A generic provider identifier could route incompatible credentials and endpoints into the wrong client, while advertising unimplemented chat or mutation behavior would create unsafe product claims.
- **Options considered:** one generic provider screen; infer provider from endpoint ports; explicit provider selection plus defensive capability gates.
- **Tradeoffs:** provider-specific endpoint policies and UI increase test cases and require legacy-profile mapping, but prevent endpoint heuristics from becoming authorization decisions.
- **Security impact:** provider secrets remain workspace-scoped; Hermes validates the credential at send time and uses ephemeral exact-origin streaming transport; workspace removal deletes the Keychain item before metadata; no Hermes mutation control is exposed without durable audit and replay controls.
- **Local-first impact:** loopback and private endpoints remain the defaults for every provider, with hosted transfer requiring explicit consent.
- **Compliance impact:** the selected provider, boundary, and advertised capability are reviewable control inputs. No compliance certification is claimed.
- **Final choice:** explicit provider selection, provider-specific validated ports, capability-gated routing, and read-only-first native delivery.
- **Follow-up:** add live private-provider contract evidence, DNS-rebinding defense, encrypted audit persistence, and reviewed approval controls before any Hermes mutation UI.

## ADR-007: Treat Apple privacy declarations as a tested source contract

- **Decision:** Bundle one reviewed `PrivacyInfo.xcprivacy` in both Apple app targets and fail local/release builds when its declarations or platform placement drift.
- **Context:** The current executable stores only an active workspace selector in `UserDefaults`, stores encrypted workspace profiles in the app container, stores keys/secrets in the device-only Keychain, has no telemetry or tracking SDK, and sends requests only to operator-configured provider infrastructure.
- **Options considered:** omit the app manifest until App Store validation; maintain untested per-platform manifests; share and validate one source manifest.
- **Tradeoffs:** exact validation intentionally fails whenever declarations change, so new storage, SDKs, telemetry, or developer-operated collection requires an explicit review instead of silently extending the existing claim.
- **Security impact:** tracking is false, tracking domains and developer/SDK collection are empty, and the only current required-reason declaration is app-only UserDefaults reason `CA92.1`. This is a source assertion, not proof of provider behavior.
- **Local-first impact:** the declaration makes the absence of THOX telemetry/collection explicit while preserving user-directed connections to local or private providers.
- **Compliance impact:** reproducible manifest evidence improves reviewability but does not replace privacy policy, App Store Connect answers, legal review, or live data-flow verification.
- **Final choice:** one source manifest plus deterministic validation at source, built-app, archive, IPA, and mounted-DMG boundaries; keep the legacy developer-hosted WebView route disabled while its collection/retention contract is unverified.
- **Follow-up:** re-audit before adding any dependency or data flow; add the public privacy/support metadata and an in-app privacy-policy surface before App Store review.

## ADR-008: Encrypt workspace profiles with explicit device-only key lifecycle

- **Decision:** Seal each workspace profile with AES-256-GCM, derive purpose keys with HKDF-SHA256 from a workspace master key, and persist only ciphertext in the app container.
- **Context:** Plaintext profile preferences exposed workspace names, endpoints, boundaries, and provider identity. A missing Keychain key must not be silently regenerated over existing ciphertext.
- **Options considered:** plaintext preferences; platform file protection alone; SQLite immediately; application-layer authenticated encryption over atomic files as the bounded first slice.
- **Tradeoffs:** atomic files avoid a new dependency and deliver encrypted onboarding now, but do not yet provide revision transactions, HMAC-obscured indexes, audit chaining, or rollback detection.
- **Security impact:** master keys are non-synchronizing `WhenUnlockedThisDeviceOnly`; AAD binds all public envelope metadata; reads are bounded; symlinks, tampering, wrong keys, and cross-workspace substitution fail closed. iOS also uses complete default file protection.
- **Local-first impact:** profile data and keys remain inside the Apple app/container and Keychain; no cloud or telemetry dependency is introduced.
- **Compliance impact:** encryption, migration, deletion ordering, and negative tests create reviewable controls without claiming certification or physical-device verification.
- **Final choice:** `WarRoomAppleInfrastructure` owns the ciphertext/key primitives; the app owns provider-aware profile encoding and revalidates provider capabilities and endpoint policy from current trusted code after decryption.
- **Follow-up:** add a transactional encrypted audit ledger with keyed chain and Keychain rollback anchor, obscure workspace routing indexes, implement retention/export and resumable deletion, and verify locked-device behavior on physical hardware.

## ADR-009: Ship a bounded encrypted audit ledger before mutation wiring

- **Decision:** Implement `DurableAuditEventStore` on Apple platforms as one workspace-scoped AES-256-GCM atomic ledger with canonical event revalidation, actor-serialized appends, ordered SHA-256 entry chaining, and digest-bound cursors. Do not enable Hermes or other mutations merely because this persistence seam exists.
- **Context:** Profiles are encrypted, but high-impact workflows also require durable redacted evidence. The current atomic encrypted file store can deliver a bounded local slice without adding SQLite or a cloud dependency.
- **Options considered:** retain in-memory recording; add SQLite and a transactional Keychain anchor immediately; build a bounded encrypted ledger now and keep rollback/policy gaps explicit.
- **Tradeoffs:** the bounded ledger provides real ciphertext-only durability and detects internal modification/reordering/substitution. A device-only Keychain version/count/head-digest anchor now rejects valid older whole ledgers and tail truncation, but append remains O(n), capacity is 10,000 entries/16 MiB, and separate instances/processes can race.
- **Security impact:** persisted events are revalidated across the decode boundary; workspace/key/AAD isolation, idempotent IDs, bounds, redacted errors, and rollback anchoring fail closed. The anchor is local device state, not an external tamper-evident or non-repudiation service.
- **Local-first impact:** audit content and keys remain in the app container and device-only Keychain with no telemetry or hosted dependency.
- **Compliance impact:** durable local evidence is a reviewable control primitive, not a compliance or non-repudiation claim.
- **Final choice:** keep the rollback-anchored ledger available as an infrastructure seam while mutation UI stays disabled. Ciphertext is committed before the anchor advances; authenticated ciphertext-ahead state recovers forward after interruption.
- **Follow-up:** add cross-instance CAS/file locking, retention/export policy, audited-operation coordination, and app composition wiring.

## ADR-010: Contract evidence gates native chat capability

- **Decision:** Open WebUI advertises native chat, streaming, and citation capabilities only after all required authenticated non-production contract evidence is captured and sanitized.
- **Context:** Current evidence proves public discovery plus unauthenticated `401` boundaries for candidate chat/history routes. That does not establish credential lifecycle, DTOs, stream frames, cancellation/errors, durable history, or citations.
- **Options considered:** infer OpenAI-compatible shapes; copy an older client contract; keep an executable missing-evidence set that fails closed.
- **Tradeoffs:** native chat stays unavailable longer, but provider drift cannot silently enable guessed traffic or persistence.
- **Security impact:** no credential or sensitive prompt is sent through an unverified route; no unsupported source-citation claim is exposed.
- **Local-first impact:** the eventual contract must preserve operator-selected local/private routing and no silent cloud fallback.
- **Compliance impact:** captured provenance and explicit capability activation make review possible; no deployed-provider assurance is claimed.
- **Final choice:** executable fail-closed evidence gate and sanitized boundary fixture.
- **Follow-up:** provision a sanctioned non-production identity and capture the nine documented evidence categories before adding DTOs or transport methods.

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
- **Follow-up:** profile revision/CAS and opaque routing indexes remain; the audit ledger, rollback anchor, and resumable deletion journal now exist. Implement retention/export and verify locked-device behavior on physical hardware.

## ADR-009: Ship a bounded encrypted audit ledger before mutation wiring

- **Decision:** Implement `DurableAuditEventStore` on Apple platforms as one workspace-scoped AES-256-GCM atomic ledger with canonical event revalidation, actor-serialized appends, ordered SHA-256 entry chaining, and digest-bound cursors. Do not enable Hermes or other mutations merely because this persistence seam exists.
- **Context:** Profiles are encrypted, but high-impact workflows also require durable redacted evidence. The current atomic encrypted file store can deliver a bounded local slice without adding SQLite or a cloud dependency.
- **Options considered:** retain in-memory recording; add SQLite and a transactional Keychain anchor immediately; build a bounded encrypted ledger now and keep rollback/policy gaps explicit.
- **Tradeoffs:** the bounded ledger provides real ciphertext-only durability and detects internal modification/reordering/substitution. A device-only Keychain version/count/head-digest anchor now rejects valid older whole ledgers and tail truncation, but append remains O(n), capacity is 10,000 entries/16 MiB, and separate instances/processes can race.
- **Security impact:** persisted events are revalidated across the decode boundary; workspace/key/AAD isolation, idempotent IDs, bounds, redacted errors, and rollback anchoring fail closed. The anchor is local device state, not an external tamper-evident or non-repudiation service.
- **Local-first impact:** audit content and keys remain in the app container and device-only Keychain with no telemetry or hosted dependency.
- **Compliance impact:** durable local evidence is a reviewable control primitive, not a compliance or non-repudiation claim.
- **Final choice:** keep the rollback-anchored ledger available as an infrastructure seam while mutation UI stays disabled. Ciphertext is committed before the anchor advances; authenticated ciphertext-ahead state recovers forward after interruption.
- **Follow-up:** cooperative cross-process file locking now exists. Add retention/export policy, audited-operation coordination, external anchoring if required, and app composition wiring.

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

## ADR-011: Serialize audit ledger and anchor as one cooperative transaction

- **Decision:** Guard the complete ledger read/verify/recovery/write/anchor sequence with a per-workspace process lock and persistent app-container Darwin `flock` file.
- **Context:** Separate store actors or helper processes could otherwise read the same head and overwrite one another despite each actor being internally serialized.
- **Options considered:** actor-only isolation; in-process lock only; SQLite transaction migration; process lock plus descriptor-backed advisory file lock.
- **Tradeoffs:** the selected lock is dependency-free, cancellation-safe, and covers current storage, but protects only cooperating writers sharing one lock root. Persistent empty lock files and a small process-lifetime lock registry are intentional.
- **Security impact:** 0600 regular single-link lock files opened with `openat`/`O_NOFOLLOW` avoid symlink and inode-split unlink races. Acquisition is bounded and failures make no ledger/anchor mutation.
- **Local-first impact:** coordination stays within the private app container and requires no daemon, database, or network service.
- **Compliance impact:** concurrent audit ordering becomes testable, but this is not external non-repudiation or protection from a privileged non-cooperating process.
- **Final choice:** two-layer cooperative locking held across ciphertext-save-before-anchor-advance ordering.
- **Follow-up:** evaluate a transactional database or privileged audit service only if multiple non-cooperating writers become a product requirement.

## ADR-012: Journal credential-first workspace deletion in device-only Keychain

- **Decision:** Persist a versioned bounded deletion stage before destructive work, then replay credential deletion, workspace key/ciphertext erasure, selector cleanup, and journal clearing idempotently.
- **Context:** A crash between credential deletion and cryptographic erasure could leave ambiguous state, while recreating a missing key over ciphertext would violate the fail-closed storage contract.
- **Options considered:** best-effort synchronous deletion; plaintext defaults flag; background database journal; device-only Keychain journal integrated with the existing single-workspace lifecycle.
- **Tradeoffs:** Keychain survives workspace-key deletion and exposes no plaintext journal file, but recovery currently runs only on lifecycle load/delete and supports one active workspace.
- **Security impact:** intent is durable before deletion; credential failure preserves recoverability; journal data is redacted, non-synchronizing, `WhenUnlockedThisDeviceOnly`, and bounded.
- **Local-first impact:** deletion coordination never leaves the device and introduces no telemetry or hosted dependency.
- **Compliance impact:** interruption recovery is reviewable evidence, not proof that every server-side copy or external export was deleted.
- **Final choice:** explicit three-stage replay with active-workspace binding and non-sensitive errors.
- **Follow-up:** add multi-workspace journaling, background recovery, export policy, and physical locked-device tests.

## ADR-013: Grant the local browser a narrow read-only filesystem capability

- **Decision:** Show the browser only for local-device workspaces and require an explicit non-persisted folder selection. Access descendants by directory descriptor with no-follow checks at every component.
- **Context:** A generic path field or recursive URL resolution could expose arbitrary files through traversal, symlinks, or stale path assumptions.
- **Options considered:** reuse legacy browser behavior; accept typed paths; persist broad bookmarks; operator-selected ephemeral root with descriptor-relative access.
- **Tradeoffs:** the first slice previews only bounded control-safe UTF-8 and requires reselection each session, but it has no write, upload, provider, or network path.
- **Security impact:** absolute/malformed/traversal paths fail closed; symlinks remain visible but cannot be followed; listings cap at 500 entries, depth at 32, and previews at 256 KiB.
- **Local-first impact:** all reads remain inside the operator-selected local namespace and file contents are never transmitted.
- **Compliance impact:** explicit provenance and a narrow capability ease review; physical picker/security-scope behavior still requires device evidence.
- **Final choice:** confined read-only text browsing before search, mutation, sharing, or bookmark persistence.
- **Follow-up:** manually validate both platform pickers, then design scoped bookmark retention and local-only search if justified.

## ADR-014: Compact audit history through authenticated ledger generations

- **Decision:** Apply explicit finite or indefinite retention by re-chaining retained events into a new ledger generation whose authenticated header commits to the exact predecessor generation, count, head digest, and lifetime commitment.
- **Context:** Removing expired events from the middle or head of a chained ledger cannot preserve the old chain, and a crash between ciphertext replacement and Keychain anchor advancement must not create an unrecoverable or rollback-accepting state.
- **Options considered:** delete only a contiguous prefix; reset the anchor after pruning; maintain an unbounded tombstone set; create a successor generation with an authenticated predecessor commitment.
- **Tradeoffs:** successor generations keep the bounded local file design and support forward recovery, but pruning is O(n), fixed-day based, and no longer retains pruned event IDs for lifetime duplicate detection.
- **Security impact:** ciphertext is saved before the anchor advances; an old generation is rejected once the anchor advances, while an authenticated exact successor can advance the anchor after a crash. Export verifies integrity and redaction before returning bounded in-memory bytes.
- **Local-first impact:** retention, anchor recovery, and export remain inside the app container and device-only Keychain with no hosted service or plaintext temporary file.
- **Compliance impact:** configurable retention and reviewable redacted export are control primitives, not legal-policy approval, a digital signature, or external non-repudiation.
- **Final choice:** 30–2555 finite days with 365 as the default plus explicit indefinite retention; exports cap at 500 events and 8 MiB.
- **Follow-up:** encrypted administrator policy persistence and native explicit apply/export UI are implemented. Add automatic scheduled execution only with an independently reviewable policy/authorization boundary, add signed export if required, and obtain legal review of domain-specific retention periods.

## ADR-015: Declare Apple export compliance at build and delivery boundaries

- **Decision:** Set `ITSAppUsesNonExemptEncryption=NO` for both Apple targets and record `usesNonExemptEncryption=false` for delivered builds while the app uses Apple CryptoKit and OS-provided transport/storage cryptography rather than a non-exempt custom cryptographic product.
- **Context:** both otherwise valid TestFlight builds remained unassignable with `MISSING_EXPORT_COMPLIANCE` until App Store Connect received an explicit classification.
- **Options considered:** answer manually for every build; omit the declaration and leave builds blocked; encode the reviewed classification in generated Info.plists and retain App Store Connect evidence.
- **Tradeoffs:** the source declaration removes a repeated release step, but it must be revisited whenever cryptographic code, use case, jurisdiction, or distribution changes.
- **Security impact:** this metadata does not weaken AES-GCM profile/audit encryption, Keychain protection, or TLS behavior.
- **Local-first impact:** local encryption remains enabled by default; export metadata does not introduce a network or hosted dependency.
- **Compliance impact:** this is an engineering classification for Apple delivery, not legal advice or a claim that every export-control obligation is satisfied.
- **Final choice:** persist the no-non-exempt-encryption declaration in `project.yml` and retain delivery/build-state evidence without storing the API private key or bearer tokens.
- **Follow-up:** obtain owner/legal re-review before adding custom cryptographic algorithms, cryptographic networking products, or materially different distribution regions.

## ADR-016: Persist one-shot mutation evidence without enabling unverified transport

- **Decision:** Back audited mutation attempts with a device-local encrypted operation ledger that globally claims correlation IDs, stores one intent and at most one terminal outcome, exposes bounded workspace-scoped pending/terminal reconciliation, and commits aggregate state to device-only Keychain. Keep production mutation composition disabled until both workspace authorization and a current live provider contract are verified.
- **Context:** The coordinator already required intent-before-transport and no automatic retry, but an in-memory or append-only seam could not survive crashes, detect a reused correlation ID after restart, distinguish pending from terminal work, or detect authenticated ledger rollback/deletion. A review UI alone could also create a false impression that actions were authorized.
- **Options considered:** enable the coordinator with the general audit ledger; use an unanchored per-workspace file; add a hosted audit service; implement a separate bounded encrypted operation ledger plus local Keychain commitment and retain a fail-closed production host.
- **Tradeoffs:** the selected store is local, dependency-free, and testable, but scans bounded workspace ledgers under one cooperative global lock and provides local tamper detection rather than external non-repudiation. Pending evidence is presented for reconciliation; it is never treated as permission to retry.
- **Security impact:** ciphertext and AAD are workspace-bound; correlation claims cannot move between workspaces; missing claims, cross-workspace outcomes, duplicate outcomes, rollback, deletion, corruption, and capacity exhaustion fail closed with redacted errors. Persistent/destructive review choices require a second confirmation, while absent authorization/credentials/store/executor keeps controls unavailable.
- **Local-first impact:** operation content, keys, commitments, and reconciliation stay in the app container and non-synchronizing device-only Keychain. No telemetry, cloud audit, or hidden fallback is introduced.
- **Compliance impact:** durable redacted lifecycle evidence and explicit human review are reviewable controls, not proof of RBAC correctness, legal authorization, provider success, or external non-repudiation.
- **Final choice:** ship and test the durable store/coordinator/UI now, but inject no production executor while authorization and live mutation evidence are missing.
- **Follow-up:** capture a sanctioned authenticated private-provider mutation session, define and verify workspace authorization/RBAC, compose the existing dependencies, then run crash/relaunch and physical-device reconciliation tests before enabling actions.

## ADR-017: Separate audit-policy confirmation from retention application

- **Decision:** Persist confirmed workspace retention policy in a separately encrypted, revision-anchored store, and require an explicit foreground-only application step before the audit lifecycle may prune.
- **Context:** A durable retention engine without app policy controls left administrators unable to review the exact active choice, while applying retention during load, save, background work, or export would make destructive behavior implicit.
- **Options considered:** apply on save; apply automatically at launch; keep policy only in memory; persist confirmed policy and expose a separate exact-confirmation action.
- **Tradeoffs:** the selected flow adds an operator step and no automatic scheduler, but keeps policy reviewable, workspace-scoped, crash-resistant, and independent from destructive execution.
- **Security impact:** AES-GCM ciphertext, workspace locks, compare-and-swap revisions, and a non-synchronizing device-only Keychain digest/revision anchor fail closed on rollback, deletion, corruption, or cross-workspace substitution. Failed verification clears stale UI state. Export never applies retention.
- **Local-first impact:** policy, audit content, and export preparation remain on device; the system exporter receives bounded redacted bytes only after the user selects a destination.
- **Compliance impact:** explicit confirmation and retained application timestamps are reviewable control evidence, not legal approval of a retention period or proof of external non-repudiation.
- **Final choice:** saving confirms policy without pruning; application requires a second destructive confirmation while the app is active; absent or unverifiable policy disables application.
- **Follow-up:** validate locked-device and interruption behavior through physical TestFlight installs; add scheduling only with a separately reviewable authorization and execution policy.

## ADR-018: Verify every active workspace selection and isolate deletion

- **Decision:** Allow multiple encrypted workspace profiles, but persist a workspace as active only after its ciphertext decrypts and its current provider and endpoint policy revalidate. Deleting the active workspace erases only its scoped credential/profile state and selects a remaining profile only after the same verification.
- **Context:** The single-active-workspace flow forced operators to destroy one private workspace before configuring another and made cross-provider testing unnecessarily risky.
- **Options considered:** keep one workspace; store a plaintext catalog; trust cached profile metadata; enumerate encrypted profiles and verify at every selection boundary.
- **Tradeoffs:** encrypted enumeration and revalidation add bounded local I/O and make corruption fail the catalog closed, but avoid plaintext endpoint/provider catalogs and stale capability trust.
- **Security impact:** the selector stores only a UUID, unknown selections do not alter it, deletion remains credential-first and journaled, and a corrupt or missing fallback cannot silently become active.
- **Local-first impact:** profiles, selectors, credentials, keys, and lifecycle state remain on device without telemetry or cloud synchronization.
- **Compliance impact:** workspace isolation and deterministic deletion evidence are implementation controls, not proof of tenant authorization, records-retention compliance, or server-side credential revocation.
- **Final choice:** expose explicit add/switch/remove controls backed by encrypted enumeration, verified selection, and isolated fallback behavior.
- **Follow-up:** add profile revision/CAS, opaque routing indexes, persisted security-scoped bookmarks, background recovery, and physical locked-device lifecycle testing.

## ADR-019: Reject URLSession hostname rewriting for DNS pinning

- **Decision:** Do not ship the attempted URLSession design that rewrites an HTTPS request hostname to a resolved IP address and restores only the HTTP `Host` header.
- **Context:** DNS rebinding resistance requires binding a validated answer to the actual connection while retaining TLS identity for the logical hostname.
- **Options considered:** URLSession IP-literal URL plus `Host`; preflight-only DNS checks; retain the current exact-origin transport and document the gate; implement a reviewed Network.framework transport that controls the peer address and TLS server name.
- **Tradeoffs:** leaving DNS rebinding as an explicit gate delays private-provider hardening, but avoids breaking virtual-host TLS or claiming a control that tests only resolver policy rather than the real connection.
- **Security impact:** a credential-free live probe reached the logical host normally but the IP-literal URL failed TLS before a usable trust challenge. The candidate was removed; current transport behavior and known-risk documentation remain unchanged.
- **Local-first impact:** no cloud dependency, telemetry, credential reuse, or endpoint exception was introduced.
- **Compliance impact:** rejected prototype evidence is not a deployed security control; DNS-bound transport remains required before high-trust private-provider release claims.
- **Final choice:** preserve the working exact-origin URLSession transport and require a connection primitive that supports both an approved peer address and original-host SNI/trust.
- **Follow-up:** design and independently review a bounded Network.framework HTTP/TLS transport, then run live private-endpoint and physical-device certificate tests before adoption.

## ADR-020: Prove numeric-peer TLS with original-host identity before transport adoption

- **Decision:** Accept Network.framework as the feasible connection primitive for DNS-bound TLS, but do not replace the current URLSession transports until a bounded HTTP/1.1/SSE implementation and cancellation coordinator are independently tested.
- **Context:** A production defense must connect to a validated numeric peer while preserving the logical hostname for SNI and system certificate verification. URLSession exposes no supported per-request resolver binding.
- **Options considered:** keep the risk documented; preflight DNS then use URLSession; weaken trust with an IP URL/custom challenge; use `NWConnection` with a numeric endpoint and `sec_protocol_options_set_tls_server_name`.
- **Tradeoffs:** Network.framework closes the address-binding primitive gap but supplies a byte stream rather than URLSession's HTTP stack. Adoption therefore requires strict status/header/body framing, chunked and SSE handling, redirect re-resolution, bounds, and exactly-once timeout/cancellation completion.
- **Security impact:** a credential-free warnings-as-errors probe preserved default trust, rejected an expired certificate, and returned HTTP 200 from every approved `webui.thox.ai` numeric peer using original-host SNI and `Host`. No custom verify block is needed for public PKI. This probe is feasibility evidence, not an app control.
- **Local-first impact:** the design adds no cloud dependency or telemetry and can enforce local/private/hosted address classes at the connection boundary.
- **Compliance impact:** keeping feasibility separate from deployed control avoids overstating DNS-rebinding resistance or private-endpoint readiness.
- **Final choice:** proceed with a shared resolver/classifier, numeric `NWConnection` factory, bounded HTTP/1.1/SSE codec, same-origin redirect re-resolution, and actor/lock-backed terminal-state coordinator as a separately reviewed slice.
- **Follow-up:** implement and threat-test that slice, then run private-CA/public-PKI and physical iOS/macOS certificate tests before switching provider traffic.

## ADR-021: Use fail-closed local manifests for Hermes and Mesh live-contract evidence

- **Decision:** Track Hermes and Mesh qualification as bounded, sanitized, offline-verifiable manifests whose `qualify` mode fails while any required category is missing.
- **Context:** Current typed clients and synthetic tests prove source behavior but not the authenticated private services, authorization boundary, cancellation semantics, or physical runtime.
- **Options considered:** infer completion from current server source; retain informal screenshots/logs; enable capture or mutation commands in the app; add local integrity validators with truthful all-missing manifests.
- **Tradeoffs:** validators add package/test surface and still require a sanctioned operator capture, but make missing evidence exact, reviewable, and resistant to traversal, symlink, size, digest, binary, and secret-retention mistakes.
- **Security impact:** evidence artifacts remain fixed-root, bounded, text-only, hash-verified, and redacted. Neither tool performs network requests, stores credentials, or enables provider mutations.
- **Local-first impact:** validation is entirely local and adds no telemetry or hosted storage.
- **Compliance impact:** manifest integrity improves auditability but is not authorization, compliance certification, or proof that a production service handled data correctly.
- **Final choice:** ship the validators and keep both checked-in manifests at truthful 0-captured status until sanctioned evidence exists.
- **Follow-up:** perform dedicated non-production captures, independently review redaction and provenance, then qualify before composing live mutation or readiness claims.

## ADR-022: Adopt DNS-bound transports for HTTPS after independent source review

- **Decision:** Compose the separately injectable Network.framework transports for bounded provider request/response and Hermes SSE traffic in every HTTPS workspace after independent source review. Retain URLSession only for explicitly validated loopback HTTP, and continue withholding signed/live readiness claims until runtime qualification succeeds.
- **Context:** The numeric-peer TLS spike established feasibility, but a deployable control also needed per-hop DNS re-resolution, complete address-set boundary validation, exact-origin redirect handling, credential timing, strict HTTP/1.1 framing, finite SSE buffering, and deterministic terminal behavior.
- **Options considered:** replace URLSession before source review; keep only the feasibility spike; add preflight DNS checks around URLSession; land injectable implementations, independently review them, then compose by validated endpoint policy before signed/live qualification.
- **Tradeoffs:** the selected sequence changes HTTPS application behavior before live/private-CA proof, but keeps the change explicit and reversible at one dependency boundary, retains loopback HTTP compatibility, and prevents shipping the already-known DNS rebinding window in the next source candidate.
- **Security impact:** connections target only validated numeric peers and retain the logical hostname for SNI and platform-default trust. Redirects remain exact-origin and trigger fresh resolution. Credentials are serialized only after boundary validation. The codec bounds ingress copies, headers, body bytes, and delivery; rejects framing ambiguity, upgrades, trailers, framed informational/no-content responses, and bytes after completion. Teredo and 6to4 addresses fail closed rather than inheriting the broad global IPv6 classification. DNS planning is cancellation-aware and consumes the same per-hop request/resource budget as the connection; Hermes resets its inactivity timer on every receive while retaining an absolute resource cap. Terminal paths cancel the connection exactly once before callers resume, and exposed errors remain typed and redacted.
- **Local-first impact:** private/local endpoints remain first-class, no resolver or telemetry service is added, and no provider payload is sent to a third party.
- **Compliance impact:** independently tested and source-composed infrastructure improves auditability but is not evidence of live provider authorization, private-CA compatibility, physical-device behavior, signed-artifact inclusion, or deployed DNS-rebinding resistance.
- **Final choice:** HTTPS feature hosts inject DNS-bound transports; explicit loopback HTTP injects URLSession; decoded legacy private/hosted HTTP injects the HTTPS-only path and therefore fails closed. Existing provider authorization, mutation, and contract-evidence gates remain unchanged.
- **Follow-up:** verify sanctioned private/public certificate paths and cancellation/redirect behavior in integrated iOS/macOS tests and physical TestFlight builds before updating any deployed-security claim.

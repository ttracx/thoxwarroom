# ThoxWarRoom Security Model

Last updated: 2026-08-23

## Assets

Credentials, session cookies, prompts, messages, documents, embeddings, model outputs, Hermes tool requests/results, fleet identifiers, device status, file paths, audit events, and release signing material.

## Trust boundaries

1. SwiftUI/platform UI to shared domain use cases.
2. Shared core to local encrypted storage and Keychain.
3. Transport adapter to each configured workspace endpoint.
4. Hermes proposal to policy/approval and then execution.
5. Main app to iOS extensions or macOS auxiliary windows.
6. Developer/release environment to Apple and GitHub signing systems.

## Primary threats and mitigations

| Threat | Required mitigation |
|---|---|
| Silent sensitive-data transfer | No implicit cloud fallback; visible workspace boundary; egress allowlist tests |
| Credential/session disclosure | Keychain; redact logs; explicit sign-out and data purge; no credentials in URLs |
| Malicious redirects/custom schemes | Require allowed schemes and normalized hosts; callback allowlist; block credentials in URL authority |
| Prompt/tool-output injection | Treat content as untrusted; never convert rendered text directly into tool authorization |
| Unauthorized Hermes action | Capability checks, least privilege, explicit approval, expiry, replay protection, append-only audit |
| Workspace file traversal | Canonicalize paths, enforce configured roots, reject symlink escape, read-only MVP |
| Cross-workspace data leakage | Workspace-scoped stores, caches, cookies, search indexes, and audit identifiers |
| Lost/stolen device | Platform data protection, encrypted local database, biometric/admin policy where required |
| Compromised dependency/build | Minimal dependencies, pinned actions/packages, SBOM, reproducible CI, signed provenance |
| Sensitive diagnostic logs | Structured event allowlist, redaction tests, user-controlled export |
| Incompatible source reuse | License inventory and owner/legal gate before using GPL-derived implementation in MIT code |

## Temporary compatibility-shell boundary

The v4.2 compatibility shell connects only to `https://webui.thox.ai` and is not
the target local-first data plane. In-app navigation requires that exact HTTPS
host, no URL credentials, and the default HTTPS port. Off-domain URLs open in
the system browser only after a user activates an HTTPS link; redirects,
scripts, custom schemes, insecure HTTP, embedded credentials, and non-default
ports are cancelled. This allowlist is intentionally narrow and must not be
expanded implicitly for authentication or convenience.

The shell uses the app's persistent `WKWebsiteDataStore.default()` so web login
can survive relaunch. Its confirmed **Sign Out & Clear Session** control removes
all WebKit website data owned by this app container, exposes clearing/success/
failure state, and reloads the canonical landing URL only after removal
completes. It does not claim server-side token revocation; physical-device and
packaged-app authentication/sign-out verification remains a release gate.

## Authentication and authorization

- Store tokens, keys, and sensitive session material in Keychain with the narrowest practical accessibility class.
- Model roles and capabilities independently of UI visibility.
- Re-authenticate or require explicit approval for high-impact actions.
- Never infer authorization from possession of an unvalidated deep link.

## Shared Core endpoint boundary

`Packages/WarRoomCore` now rejects workspace endpoints with unsupported schemes,
missing or malformed hosts, URL credentials, disallowed explicit ports, query or
fragment components, or decoded `..` path traversal. Loopback, private-network,
and hosted destinations are distinct values. Hosted access requires affirmative
authorization and HTTPS; private-network HTTP and non-default ports require an
explicit policy choice. These checks perform no DNS or network access.

This syntactic classification is only the first egress gate.
`WarRoomAppleInfrastructure` now supplies a cookie-free/cache-free ephemeral
transport with exact-origin redirects, bounded request/response bodies, typed
non-sensitive failures, and bearer injection only at send time. It does not yet
compare resolved addresses with the declared boundary on every connection, so
DNS rebinding and live TLS/private-endpoint validation remain integration gates.

Audit events redact every field marked sensitive plus secret-like field names
before they cross the recording seam. Full prompts, documents, credentials, and
tokens must never be reintroduced by a concrete audit store.

`EncryptedDurableAuditEventStore` is the current concrete Apple persistence
seam. It revalidates decoded events, encrypts one bounded ledger per workspace,
serializes appends within one actor instance, chains ordered entries, and binds
page cursors to the workspace and preceding digest. AES-GCM protects the whole
ledger from ciphertext modification and substitution. A fixed-width
`WhenUnlockedThisDeviceOnly` Keychain version/count/head-digest anchor rejects
older valid ciphertext, valid tail truncation, divergent prefixes, and missing
or invalid anchors, while allowing authenticated ciphertext-ahead crash
recovery. A process-wide per-root/workspace lock plus a persistent 0600
app-container `flock` file serializes the complete ledger-and-anchor transaction
across cooperative actors/processes with bounded, cancellation-safe acquisition.
This is advisory coordination, not external non-repudiation, so mutation
workflows remain disabled pending authorization and policy wiring.

## Storage and retention

- Workspace profile payloads are AES-256-GCM encrypted with a fresh nonce and HKDF-derived purpose key. Associated data binds workspace, collection, record, algorithm, key reference, and canonical timestamps.
- Per-workspace 256-bit master keys are non-synchronizing `WhenUnlockedThisDeviceOnly` Keychain items. Normal reads/writes never recreate missing keys over ciphertext.
- Ciphertext files use bounded reads, atomic writes, private permissions, backup exclusion, symlink rejection, and complete iOS file protection.
- Provider identity and endpoint policy are revalidated from current code after decryption; persisted capability sets are never trusted.
- Multiple encrypted profiles may coexist. The active selector contains only a workspace UUID; selection succeeds only after decrypting and revalidating that profile, and deleting the active workspace verifies a remaining encrypted profile before persisting a deterministic fallback selector.
- Legacy plaintext profile preferences remain recoverable until encrypted write/read-back and active-selector persistence succeed.
- Make retention, deletion, export, and cache clearing explicit.
- Use separate `WKWebsiteDataStore` boundaries if web compatibility remains during migration.
- Do not enable iCloud synchronization for sensitive stores by default.

## Audit logging

Record authentication outcomes, workspace/profile changes, Hermes approvals/denials, tool execution results, file mutations, automation changes, export/deletion, and policy failures. Do not record secrets, full prompts, full documents, or unrestricted tool output by default.

## Current known risks

- Native onboarding encrypts validated profile payloads locally. `UserDefaults` contains only the active workspace UUID and temporary legacy migration evidence; Open WebUI and Hermes credentials use a separate workspace-scoped, non-synchronizing `WhenUnlockedThisDeviceOnly` Keychain adapter. Workspace deletion removes the provider secret before cryptographic profile erasure and preserves metadata if credential deletion fails. Authentication is not yet verified against a real private provider.
- Hermes review is intentionally read-only. It requires a stored workspace credential, validates the Hermes provider capability, and exposes no approve or stop operation. The app concurrently loads status and an incremental URLSession SSE stream using an ephemeral, cookie-free, cache-free session; redirects must preserve exact origin, delivery is bounded, cancellation tears down the task/session, and errors are non-sensitive. A transport-neutral coordinator claims a scoped correlation ID durably before approval/stop transport, rejects replay, never retries, and records a bounded outcome or explicit indeterminate state. The offline Hermes evidence qualifier rejects unsafe or secret-bearing bundles and truthfully reports 0 of 11 live categories captured; reconnect/cursor semantics, provider authorization, and live-provider evidence remain unverified.
- MeshStack War Room is intentionally read-only. It requires the exact Mesh provider identity, `.warRoomStatus` capability, a workspace-scoped Keychain credential, and a canonical operator-entered MeshID before transport. Devices, topology, and events load independently so verified partial results retain provenance; no control-plane mutation is exposed. Its offline evidence qualifier rejects secrets, private capture UUIDs, unsafe paths, and malformed artifacts and truthfully reports 0 of 10 live categories captured. The contract remains source-defined and synthetic-fixture-tested, not live-verified.
- Hermes mutations remain disabled in the production host until workspace authorization and the current live mutation contract are verified. The implemented one-shot path atomically persists a redacted intent before transport, rejects correlation replay across workspace ledgers, never retries transport, records at most one terminal outcome, and exposes bounded pending/terminal crash reconciliation. Workspace ledgers are independently AES-256-GCM sealed; a device-only Keychain commitment detects authenticated rollback or deletion. The human-review UI shows exact operation scope and requires a second confirmation for persistent/destructive decisions, but the presence of UI and storage is not authorization.
- Open WebUI native chat remains fail-closed. Its offline evidence qualifier accepts only bounded text artifacts under a fixed root, rejects traversal/symlinks/binary or secret-like content, verifies hashes and byte counts, and requires all nine authenticated contract categories before qualification. The checked-in manifest truthfully records 0 captured and 9 missing.
- Current application source composes Network.framework provider and Hermes SSE transports for every HTTPS workspace. Each hop binds to a fully validated numeric DNS snapshot while retaining original-host SNI/default trust. Their shared HTTP/1.1 parser bounds headers, bodies, delivery, and ingress copies; rejects ambiguous framing, trailers, upgrades, and framed 1xx/204 responses; and their terminal coordinator cancels exactly once before resuming callers. DNS planning is cancellation-aware, request/resource and stream-inactivity timeouts cover resolution and transfer, and hosted planning rejects Teredo and 6to4 transition ranges. URLSession compatibility remains only for explicitly validated loopback HTTP; decoded legacy private/hosted HTTP profiles receive the HTTPS-only transport and fail closed. This composition is independently source-tested but not yet built into a signed artifact, live-private-endpoint-tested, or physically verified, so released/running builds must not claim DNS-rebinding resistance yet.
- The hosted compatibility implementation still uses the default persistent website data store and lacks verified server-retention and embedded-domain evidence. Its user-facing route is therefore feature-disabled even for an exact authorized origin; re-enabling requires a reviewed privacy contract and workspace-isolated storage.
- There is no encrypted chat/document history, RBAC, or verified full-data export workflow. The audit writer lock is advisory and only coordinates cooperating processes using the same app-container root. Retention is explicit (30–2555 days or indefinite), compaction advances an authenticated generation/predecessor chain, and the confirmed policy is separately AES-GCM sealed with workspace locks, compare-and-swap revisions, and a device-only non-synchronizing Keychain digest/revision anchor. Saving a policy never prunes; application requires a second exact destructive confirmation and is cancelled when the app leaves the foreground. Export is bounded, redacted, integrity-verified, prepared in memory, and written only by the system exporter to a user-selected destination. There is no automatic scheduler, signed export, or external non-repudiation. Workspace deletion is journaled and resumable when lifecycle load/delete runs; multiple encrypted workspaces and verified fallback selection are supported, but there is no background recovery worker. Ciphertext paths currently expose raw workspace UUID routing metadata, and physical locked-device/file-protection behavior is not yet evidenced. Both app targets bundle a validated privacy manifest that declares no tracking domains, no developer/SDK data collection, and app-only UserDefaults reason `CA92.1`; this matches the current direct required-reason API use and must be reviewed again whenever storage, telemetry, SDKs, or network ownership changes.
- The macOS release script requires Developer ID Application signing, rejects `get-task-allow`, uses a Keychain-backed notary profile, staples before final staging, and validates the exact final DMG and mounted app. A live THOX Developer ID/notarized run and clean-device behavior remain unproven. Separately, iOS and native macOS App Store build 5 artifacts from source `2c299ef` are Apple-processed `VALID`, `IN_BETA_TESTING`, and assigned to the THOX internal TestFlight group. Export compliance is declared in both source Info.plists as no non-exempt encryption because the app uses Apple CryptoKit/OS-provided cryptography; that classification requires re-review if cryptographic implementation or distribution scope changes. App Store Connect reports an iPad installation only for iOS build 4, but direct build 5 launch/session evidence is absent; the connected iPhone remains on build 3 and the last observed Mac state showed build 4 uninstalled.
- The published v4.2 macOS app is a development-signed preview rejected by Gatekeeper, not a production distribution.

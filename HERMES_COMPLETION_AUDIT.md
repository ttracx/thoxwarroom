# Hermes Completion Audit

Last verified: 2026-08-23

## Executive finding

The earlier Hermes-era product was broad, but current `main` is no longer the seven-file v4.2 web shell found at the start of this audit. It is now a clean-room native SwiftUI iOS/macOS foundation with explicit workspaces, encrypted profiles, provider-scoped credentials, read-only Open WebUI/Hermes/MeshStack surfaces, an encrypted durable-audit implementation seam, and a live Hermes event-streaming seam. It is still not a completed private-chat and agent-control release.

Evidence must remain separated:

- **Historical implementation evidence:** tag `v4.1.0` / commit `96ca830` contains the former Flutter product and its Hermes, War Room, chat, automation, workspace, memory, insights, and platform modules. This is useful behavior inventory, not current runtime or release evidence.
- **Current source evidence:** current native packages implement typed, bounded, testable contracts without copying the GPL-era runtime.
- **Current local validation:** 155 package tests pass with warnings-as-errors; 71 integrated macOS app tests pass; three SPDX generator tests, deterministic project/assets, privacy checks, and the generic iOS Simulator test build pass.
- **Current signing evidence:** a distribution-signed IPA for `DVJ6Z5343U.ai.thox.warroom` was exported before the latest source wave, and a newer Apple Distribution Mac App Store package was exported from this wave. Fresh final-revision artifacts remain required after documentation reconciliation.
- **Current external blockers:** App Store Connect has no app record for `ai.thox.warroom`; Apple requires that record to be created on the website. GitHub jobs stop before all steps because the account is locked by a billing issue. A Developer ID Application certificate is unavailable for macOS notarization.

## Hermes-era inventory and current disposition

| Area | Historical evidence | Current native status | Remaining gate |
|---|---|---|---|
| Open WebUI chat | Streaming, history, folders, citations, files, voice | Bounded discovery and protected model catalog; executable native-chat evidence gate stays fail-closed | Capture a sanitized authenticated non-production credential/request/response/stream/history/citation contract |
| Hermes Agent | Runs, jobs, streaming, approvals, schedules, provenance | Typed run/status/approval/stop contracts and app-wired read-only review over bounded incremental URLSession SSE | Reconnect/cursor contract, live private-service evidence, durable pre-send approval coordinator |
| War Room | Fleet, Mesh, routes, alerts; some mock data | Credential- and canonical-MeshID-gated read-only Mesh dashboard with provenance and partial states | Sanctioned private gateway capture and device/Mac runtime evidence |
| Workspace | Models, knowledge, tools, skills, file browser | Validated provider profiles encrypted with device-only keys, resumable credential-first deletion, and confined read-only local text browser | Profile revision/CAS, opaque routing index, multi-workspace lifecycle, persisted security-scoped bookmarks |
| Audit | Event intent in historical features | Redaction-revalidated, workspace-scoped AES-GCM ledgers with ordered chain, bounded paging, device-only Keychain head anchor, and cooperative cross-process serialization | Retention/export, external anchoring, app mutation wiring |
| Automations and mutations | Editors, schedules, cards | Intentionally absent | RBAC, policy, durable intent/outcome audit, replay controls, human approval |
| Platform/release | iOS/macOS integrations and historical workflows | Native targets, deterministic project generation, privacy manifest, SPDX SBOM, signed iOS and Mac App Store export paths | App record, iOS/macOS TestFlight upload/install, and Developer ID notarized Mac artifact |

The historical modules are not treated as production-ready. Git proves source existed; it does not prove a deployed backend contract, secure workflow, physical-device result, or which agent authored the work. Git records the commits as THOX Engineering/Tommy, not an identity named “Hermes Agent.”

## What current `main` completes

- Native SwiftUI targets for macOS 14+ and iOS 17+ generated from `project.yml`.
- Explicit local-machine, private-network, and consented-hosted workspace boundaries with provider capability routing.
- AES-256-GCM workspace-profile storage using HKDF purpose keys, device-only non-synchronizing Keychain master keys, atomic bounded ciphertext files, backup exclusion, and complete iOS data protection.
- Workspace-scoped Keychain provider credentials and exact-origin, cookie-free/cache-free bounded transport.
- Open WebUI discovery and model-catalog surface. Native chat capabilities stay disabled until authenticated contract evidence exists.
- Credential-gated, read-only Hermes review that concurrently loads status and a concrete URLSession live byte stream with bounded incremental SSE parsing, cancellation, cross-run rejection, terminal-state mapping, and bounded event retention.
- Read-only MeshStack War Room devices/topology/events dashboard.
- Encrypted durable-audit store with workspace isolation, idempotent event IDs, canonical redaction revalidation, ordered internal chain, bounded capacity, time filtering, digest-bound cursors, and a device-only Keychain head anchor.
- Cooperative cross-actor/process audit transaction serialization with cancellation-safe bounded locking and no lock-file unlink race.
- Resumable device-only Keychain deletion journal preserving credential-first erasure across interruption.
- Local-boundary-only, operator-selected read-only workspace browser with descriptor-relative path confinement and bounded text preview.
- Deterministic SPDX 2.3 source inventory and separate iOS, Mac App Store/TestFlight, and Developer ID release paths.
- Deterministic unsigned validation and tested Apple privacy declarations.

## Material gaps and risks

1. Native authenticated chat is contract-blocked; unauthenticated `401` route boundaries do not establish safe DTO, streaming, history, or citation shapes.
2. Hermes live review has no reconnect/cursor semantics or live private-service evidence; URLProtocol and simulator tests prove the client boundary, not deployed-provider interoperability.
3. Hermes approvals and other mutations remain unavailable because durable intent/outcome coordination, authorization, replay control, and UI review are not wired.
4. The device-only Keychain head anchor rejects whole-ledger rollback, divergent prefixes, and valid tail truncation, and recovers when ciphertext is ahead after a crash. This is a local rollback control, not external non-repudiation evidence.
5. Audit locks are advisory and protect only cooperative writers sharing the same app-container lock root; each append remains O(n), with a 10,000-entry/16 MiB cap.
6. Audit retention/export, encrypted chat/document history, RBAC, opaque routing indexes, multi-workspace lifecycle, and background deletion recovery remain unfinished.
7. DNS-rebinding resistance, live endpoint authentication, physical locked-device behavior, and packaged-app workflows are not proven.
8. Neither iOS nor macOS TestFlight can accept a build until an App Store Connect website record exists. Direct macOS release also cannot complete without Developer ID Application signing/notarization credentials.
9. Remote CI is not evidence while GitHub jobs have zero steps due the account billing lock.
10. The historical app is GPL-3.0 while current native `main` is MIT. Legacy implementation source must not be copied without an explicit legal choice.

## Source references

- Current native app: `App/`, `Tests/`, `Packages/`, `project.yml`, `scripts/`
- Current contracts: `docs/current_service_contracts.md`
- Current release gates: `release_evidence.md`
- Current native rewrite origin: commit `1396753`
- v4.2 shell release: tag `v4.2.0`, commit `138a704`
- Hermes-era baseline: tag `v4.1.0`, commit `96ca830`
- Major Hermes-era feature commit: `cd33bfc`

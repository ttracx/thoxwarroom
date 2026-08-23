# Hermes Completion Audit

Last verified: 2026-08-23

## Executive finding

The earlier Hermes-era product was broad, but current `main` is no longer the seven-file v4.2 web shell found at the start of this audit. It is now a clean-room native SwiftUI iOS/macOS foundation with explicit workspaces, encrypted profiles, provider-scoped credentials, read-only Open WebUI/Hermes/MeshStack surfaces, an encrypted durable-audit implementation seam, and a live Hermes event-streaming seam. It is still not a completed private-chat and agent-control release.

Evidence must remain separated:

- **Historical implementation evidence:** tag `v4.1.0` / commit `96ca830` contains the former Flutter product and its Hermes, War Room, chat, automation, workspace, memory, insights, and platform modules. This is useful behavior inventory, not current runtime or release evidence.
- **Current source evidence:** current native packages implement typed, bounded, testable contracts without copying the GPL-era runtime.
- **Current local validation:** 119 package tests pass with warnings-as-errors; the integrated unsigned pipeline passes deterministic project/assets, privacy checks, macOS tests, and a generic iOS Simulator test build.
- **Current signing evidence:** a distribution-signed IPA for `DVJ6Z5343U.ai.thox.warroom` was exported before the latest source wave. A fresh archive is required for the new revision.
- **Current external blockers:** App Store Connect has no app record for `ai.thox.warroom`; Apple requires that record to be created on the website. GitHub jobs stop before all steps because the account is locked by a billing issue. A Developer ID Application certificate is unavailable for macOS notarization.

## Hermes-era inventory and current disposition

| Area | Historical evidence | Current native status | Remaining gate |
|---|---|---|---|
| Open WebUI chat | Streaming, history, folders, citations, files, voice | Bounded discovery and protected model catalog; executable native-chat evidence gate stays fail-closed | Capture a sanitized authenticated non-production credential/request/response/stream/history/citation contract |
| Hermes Agent | Runs, jobs, streaming, approvals, schedules, provenance | Typed run/status/approval/stop contracts, read-only buffered app review, and incremental bounded SSE seam | Concrete Apple streaming transport, reconnect/cursor contract, live private-service evidence, durable pre-send approval coordinator |
| War Room | Fleet, Mesh, routes, alerts; some mock data | Credential- and canonical-MeshID-gated read-only Mesh dashboard with provenance and partial states | Sanctioned private gateway capture and device/Mac runtime evidence |
| Workspace | Models, knowledge, tools, skills, file browser | Validated provider profiles encrypted with device-only keys | Revision/CAS, opaque routing index, resumable deletion, browser slice |
| Audit | Event intent in historical features | Redaction-revalidated, workspace-scoped AES-GCM ledgers with ordered internal SHA-256 chain and bounded paging | Keychain monotonic anchor, multi-instance serialization, retention/export, app mutation wiring |
| Automations and mutations | Editors, schedules, cards | Intentionally absent | RBAC, policy, durable intent/outcome audit, replay controls, human approval |
| Platform/release | iOS/macOS integrations and historical workflows | Native targets, deterministic project generation, privacy manifest, signed iOS export path | TestFlight record/upload/install and Developer ID notarized Mac artifact |

The historical modules are not treated as production-ready. Git proves source existed; it does not prove a deployed backend contract, secure workflow, physical-device result, or which agent authored the work. Git records the commits as THOX Engineering/Tommy, not an identity named “Hermes Agent.”

## What current `main` completes

- Native SwiftUI targets for macOS 14+ and iOS 17+ generated from `project.yml`.
- Explicit local-machine, private-network, and consented-hosted workspace boundaries with provider capability routing.
- AES-256-GCM workspace-profile storage using HKDF purpose keys, device-only non-synchronizing Keychain master keys, atomic bounded ciphertext files, backup exclusion, and complete iOS data protection.
- Workspace-scoped Keychain provider credentials and exact-origin, cookie-free/cache-free bounded transport.
- Open WebUI discovery and model-catalog surface. Native chat capabilities stay disabled until authenticated contract evidence exists.
- Credential-gated, read-only Hermes review plus a transport-neutral live byte stream client with bounded incremental SSE parsing, cancellation, and cross-run rejection.
- Read-only MeshStack War Room devices/topology/events dashboard.
- Encrypted durable-audit store with workspace isolation, idempotent event IDs, canonical redaction revalidation, ordered internal chain, bounded capacity, time filtering, and digest-bound cursors.
- Deterministic unsigned validation and tested Apple privacy declarations.

## Material gaps and risks

1. Native authenticated chat is contract-blocked; unauthenticated `401` route boundaries do not establish safe DTO, streaming, history, or citation shapes.
2. Hermes app review still uses the buffered compatibility client. The new live stream seam has no concrete URLSession adapter, reconnect/cursor semantics, or live private-service evidence.
3. Hermes approvals and other mutations remain unavailable because durable intent/outcome coordination, authorization, replay control, and UI review are not wired.
4. The audit ledger detects internal modification, reordering, and substitution but not replacement with an older valid whole ledger or valid tail truncation; a Keychain monotonic anchor is still required.
5. Separate audit-store instances/processes can race because the backing store has no CAS or file lock; each append is O(n), with a 10,000-entry/16 MiB cap.
6. Audit retention/export, encrypted chat/document history, RBAC, opaque routing indexes, and resumable deletion remain unfinished.
7. DNS-rebinding resistance, live endpoint authentication, physical locked-device behavior, and packaged-app workflows are not proven.
8. TestFlight cannot accept a build until an App Store Connect website record exists. macOS release cannot complete without Developer ID Application signing/notarization credentials.
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

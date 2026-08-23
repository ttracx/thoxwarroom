# Hermes Completion Audit

Last verified: 2026-08-23

## Executive finding

Hermes-era work is substantial and recoverable from Git history, but it is not present in the current v4.2 application. The current `main` branch is a small native SwiftUI shell around `https://webui.thox.ai`; it is not yet the iOS/macOS War Room product described by v4.1.

This distinction matters:

- **Historical implementation evidence:** tag `v4.1.0` / commit `96ca830` contains a Flutter application with 555 files under `lib/`, 359 files under `test/`, and dedicated Hermes, War Room, workspace, chat, automation, memory, insight, Spotlight, terminal, and platform integration modules.
- **Current source evidence:** tag `v4.2.0` / commit `138a704` contains seven Swift application files and one XCTest file with eight model/state tests.
- **Current build evidence:** the checked-in Xcode project passed all eight macOS tests and built successfully for a generic iOS Simulator on 2026-08-23. `xcodegen` was absent on the audit host, so regeneration from `project.yml` was not verified.
- **Release evidence:** GitHub release `v4.2.0` publishes one macOS arm64 DMG. The released app is Apple Development signed, carries `get-task-allow`, has no stapled notarization ticket, and is rejected by Gatekeeper. There is no iOS artifact in that release and no current GitHub Actions workflow in `main`.
- **Runtime reachability evidence:** `https://webui.thox.ai/` returned HTTP 200 with valid TLS during the audit. That proves endpoint reachability only, not authentication, session persistence, Hermes connectivity, or a completed user workflow.

## What Hermes-era work had completed

The following modules exist at `v4.1.0` and can be mined for contracts, behavior, test cases, and UX requirements:

| Area | Historical evidence | Current v4.2 status | Disposition |
|---|---|---|---|
| Open WebUI chat | Streaming chat, history, folders, search, citations, markdown, files, voice | Remote web UI only | Rebuild the minimum native vertical slice, then expand |
| Hermes Agent | 27 source files for config, capabilities, sessions, jobs, streaming, approvals, schedules, provenance, local-document trust | Absent | Recreate behavior from independently captured contracts and specifications in a shared Swift core |
| War Room | Fleet, Mesh, ThoxRoute, and alerts models/providers/views; the provider emits mock/hard-coded data | Absent | Treat as prototype UX and rebuild against verified contracts |
| Workspace | Models, knowledge, tools, skills plus a seven-file workspace browser | Absent | Rebuild read-only first; gate mutations with explicit approval |
| Automations | Models, provider, editor, cards, page | Absent | Defer writes until audit and approval controls exist |
| Memories | CRUD models/provider/views | Absent | Rebuild with workspace isolation and retention controls |
| Insights | Local usage summaries and charts | Absent | Rebuild from local audit data; no telemetry |
| Desktop Spotlight | Six-file floating chat implementation | Absent | macOS-specific post-MVP slice |
| Platform integrations | iOS share sheet, widgets, App Intents, voice, CarPlay; macOS desktop behaviors | Absent | Separate platform workstreams after shared core stabilizes |
| Privacy/security docs | `PRIVACY_POLICY.md`, `SECURITY.md`, architecture/build docs | Deleted in v4.2 rewrite | Restore and update before distribution |
| Automated release | Historical tagged multi-platform workflow | Deleted; historical CI runs failed/cancelled | Build a new native signed release workflow |

The audit does **not** claim these historical modules were production-ready. Their presence and test inventory are useful evidence of implemented intent, but live Hermes, device, signing, notarization, TestFlight, and App Store workflows must be re-verified against current services.

## What v4.2 currently completes

- Shared SwiftUI application entry point for macOS 14+ and iOS 17+.
- Persistent `WKWebsiteDataStore.default()` session container.
- Branded loading and error/retry states.
- Off-domain navigation routed to the system browser.
- macOS sandbox, hardened runtime, and outbound network entitlement.
- XcodeGen source configuration and local build scripts.
- Eight unit tests for the URL policy and load-state model.
- Current macOS test pass and iOS Simulator build pass.

## Material gaps and risks

1. **Product regression:** Hermes, War Room, local data, direct/local providers, native chat, approvals, workspace, automation, memories, insights, and platform integrations are absent from current source.
2. **Local-first mismatch:** the only configured application destination is a public hosted endpoint. There is no local endpoint configuration, discovery, offline data plane, or explicit local/cloud boundary.
3. **Navigation policy weakness:** policy is host-only and does not explicitly require HTTPS or handle authentication callback allowlists. A URL with the allowed host and an unsafe scheme is not rejected by the model.
4. **Unverified sensitive-data boundary:** a persistent web data store holds session material, but there is no documented sign-out/data purge, retention policy, workspace isolation, or audit trail.
5. **Release gap:** the public v4.2 release has a macOS DMG only. Signing/notarization evidence was not established, and the iOS archive/TestFlight path was not verified.
6. **CI gap:** current `main` has no GitHub Actions workflow. The latest visible historical CI runs failed or were cancelled.
7. **Reproducibility gap:** build instructions require XcodeGen, but the audited host does not have it installed.
8. **Test coverage gap:** current tests do not instantiate a live `WKWebView`, exercise authentication, validate cookie persistence, test deep links, or cover any Hermes/War Room behavior.
9. **Documentation gap:** the current README describes the shell accurately but the former privacy, security, building, contribution, and architecture documents were removed.
10. **Identity/release risk:** one bundle identifier is shared across targets; App Store Connect records, provisioning profiles, entitlements, privacy manifests, and distribution identities require owner-side verification.
11. **License decision:** the historical Conduit-derived application is GPL-3.0 while current native `main` is MIT. Legacy source must not be copied into the MIT target without an explicit owner/legal decision; the default plan is a clean-room native implementation from independently captured service contracts and requirements.
12. **iOS distribution state:** the icon catalog and App Store Connect credential plumbing were repaired on 2026-08-23. A distribution-signed/provisioned IPA was exported and verified, but upload is blocked until an App Store Connect app record is created for the already-registered `ai.thox.warroom` bundle ID.

## Source references

- Current shell: `App/`, `Tests/`, `project.yml`, `scripts/`
- Current native rewrite: commit `1396753`
- Current release: tag `v4.2.0`, commit `138a704`
- Hermes-era baseline: tag `v4.1.0`, commit `96ca830`
- Major Hermes-era feature commit: `cd33bfc` (105 changed files, 8,302 additions, 2,480 deletions)
- Historical architecture: `git show v4.1.0:docs/architecture.md`
- Historical build guide: `git show v4.1.0:docs/BUILDING.md`

Git records the historical commits as authored by THOX Engineering/Tommy, not an identity named “Hermes Agent.” The repository proves what source existed; it cannot prove which agent produced it.

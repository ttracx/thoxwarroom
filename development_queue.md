# ThoxWarRoom Multi-Team Development Queue

Last updated: 2026-08-23

## Team topology

| Team | Ownership | May merge when |
|---|---|---|
| Team Core | Shared Swift package, domain models, persistence, transport, workspace identity, audit | Contract, unit, migration, and egress-policy tests pass |
| Team iOS | iPhone navigation, auth UX, chat UI, share extension, App Intents, device QA | Core APIs are versioned; simulator and physical-device flows pass |
| Team macOS | Windowing, sidebar, chat/War Room UI, Spotlight, packaging | Core APIs are versioned; app sandbox and runtime flows pass |
| Team Hermes/War Room | Hermes adapters, approvals, jobs, workspace browser, fleet/mesh/route adapters | Backend fixtures and live private-environment contract tests pass |
| Team Security/QA/Release | Threat tests, accessibility, privacy manifest, CI, signing, notarization, TestFlight | Independent release matrix and clean-device smoke pass |

Team Core defines interfaces; platform teams own presentation and OS integration; feature teams provide adapters/use cases; Security/QA owns independent gates. No team may bypass the shared workspace and audit boundaries.

## Dependency sequence

```mermaid
flowchart LR
    P0[P0 Evidence and contracts] --> P1[P1 Secure workspace foundation]
    P1 --> P2[P2 Private chat slice]
    P1 --> P3[P3 Hermes review console]
    P1 --> P4[P4 Read-only War Room]
    P2 --> P5[P5 iOS and macOS productivity]
    P3 --> P5
    P4 --> P5
    P5 --> P6[P6 Signed release]
```

## Active backlog

| ID | Priority | Status | Owner | Files/modules affected | Acceptance criteria | Tests | Security/docs | Next action |
|---|---:|---|---|---|---|---|---|---|
| WR-000 | 9.6 | Ready | Architecture + owner/legal | License inventory and product baseline | Written choice: clean-room MIT native implementation or GPL distribution; protected v4.1 reference rules | License/source provenance scan | ADR and notices | Approve the licensing baseline |
| WR-001 | 9.4 | Public/current-source contracts captured; authenticated live fixtures pending | Core + Hermes | `docs/current_service_contracts.md`; sanitized public fixture; provider packages | Open WebUI public behavior and current Hermes/War Room source contracts captured without copying legacy implementation | Provider Codable fixtures, malformed input, stream cancellation | Sanitized fixture; observed/source/unverified labels | Capture authenticated non-production fixtures after a test account/private environment is available |
| WR-002 | 9.2 | Core, onboarding, Keychain, and bounded transport primitives implemented; app wiring pending | Core + Security + platform | `Packages/WarRoomCore`; `Packages/WarRoomAppleInfrastructure`; `App/WorkspaceOnboarding*` | Validated boundary/consent; metadata-only profile persistence; workspace-scoped non-sync Keychain vault; exact-origin cookie/cache-free transport | 16 Core + 14 infrastructure + 9 onboarding tests; integrated macOS 21/21 and generic iOS test build pass | README, ADR-004/005, security boundary, accessible privacy states | Wire credential enrollment and reachability through the concrete adapters, then verify a real private endpoint |
| WR-003 | 8.8 | Storage design pending; Keychain primitive complete | Core | Encrypted workspace store, migrations, audit | Workspace isolation, deletion/export, crash-safe migration | Migration, corruption, cross-workspace tests | Retention and audit schema | Select encrypted platform storage and implement a durable redacted audit store |
| WR-004 | 8.5 | Discovery/model adapter implemented; authenticated chat contract unverified | Core + iOS + macOS | `Packages/WarRoomOpenWebUI`; native chat and streaming | Public discovery and model catalog are bounded; authenticate, stream/cancel/retry, persist/relaunch, cite sources remain | 14 offline adapter tests; UI/offline/reconnect/cancellation pending | Sensitive-log redaction; observed vs provisional fixtures | Capture authenticated non-production chat/token contracts before implementing chat |
| WR-005 | 8.7 | Buffered Hermes contract client implemented; live stream/review UI pending | Hermes + Security | `Packages/WarRoomHermes`; sessions, approvals, audit | Typed runs/status/events/stop/approval; UI confirmation, durable pre-send audit, replay rejection, and live stream remain | 17 offline route/model/SSE/bounds/cancellation tests; live/replay/injection pending | Package documents approval/audit boundary | Add streaming transport seam, then build read-only session UI before approval integration |
| WR-006 | 8.1 | Blocked by WR-001/2 | Hermes/War Room | Fleet, mesh, route, alert adapters | Provenance, last-updated, stale/error/empty states against real endpoints | Adapter fixtures, timeout, partial failure | Avoid device identifiers in logs | Normalize health contracts |
| WR-007 | 7.8 | Blocked by WR-003/5 | Hermes + platform | Read-only workspace browser | Search/view within root; no traversal or symlink escape | Path fuzz, symlink, size, encoding | Root policy and audit | Port v4.1 path-policy cases |
| WR-008 | 7.5 | Blocked by WR-004/5 | iOS | Share extension, App Intents, deep links | Share text/file into selected workspace with preview and confirmation | Extension lifecycle, locked Keychain, deep-link validation | Privacy manifest/data sharing | Ship one share-to-draft flow |
| WR-009 | 7.4 | Blocked by WR-004/5 | macOS | Sidebar, commands, Spotlight window | Multi-window lifecycle, keyboard access, no action bypass | UI, focus, relaunch, sandbox | Accessibility and audit | Ship native sidebar and command routing |
| WR-010 | 9.0 | Implemented locally; GitHub billing blocked | Security/QA/Release | `.github/workflows`, pinned bootstrap, unsigned CI | Every PR regenerates deterministically, tests every package with warnings as errors, and builds/tests both targets without release secrets | 61 package tests, 21 macOS tests, deterministic assets/project, generic iOS Simulator test build all pass locally | Workflow has read-only contents permission and no signing/upload/notary operations | Unlock GitHub billing and rerun; remote jobs stop before all steps with the account-lock annotation |
| WR-011 | 8.0 | Implemented 2026-08-23 | Core + platform | Current `WKWebView` compatibility shell | Exact-host HTTPS in-app policy; only safe user-activated external links; automatic redirect denial; confirmed sign-out purge with explicit state | Navigation matrix plus injected persistent-store purge/state tests; macOS tests and iOS Simulator build | Temporary hosted boundary documented; workspace-scoped stores remain WR-002/003 | Re-verify live authentication/sign-out on physical iPhone and packaged Mac |
| WR-012 | 7.2 | Implemented 2026-08-23 | Release | `.tools`, bootstrap scripts, README | One command checksum-verifies repository-local XcodeGen 2.46.0 and validates a clean clone without global installation | `scripts/bootstrap.sh`; cached-version and archive-digest checks | Tool directory ignored; HTTPS-only download; pinned release digest | Re-run bootstrap on a second clean host when available |
| WR-013 | 8.6 | Implemented; ASC record pending | iOS + Release | `Assets.xcassets`, icon generator, upload script | Catalog validates without warnings; documented ASC variables match; signed archive and IPA export succeed | Validator and direct `actool` checks pass; generic Simulator test build passes; exported IPA signature/provisioning verified | Key remains external with mode 600; validation suppresses bearer token output | Create the App Store Connect app record for `ai.thox.warroom`, then rerun upload and verify processing/install |
| WR-014 | 9.1 | Implemented; live signing pending | macOS + Release | `scripts/build_macos.sh`, release docs | Developer ID signing; no `get-task-allow`; staple before final staging; final DMG app passes Gatekeeper | Script now gates on `codesign`, `stapler`, `spctl`, checksum; credential-free unsigned packaging validated locally | No secrets in arguments; Keychain notary profile only | Run with Developer ID identity and `NOTARY_PROFILE`, then retain final validation output as release evidence |

## Milestones and evidence gates

### Milestone 0 — Baseline and contracts

- Preserve `v4.1.0` as read-only reference.
- Record the license/product decision before reusing any legacy implementation.
- Produce sanitized fixtures for current Hermes/Open WebUI/War Room endpoints.
- Restore CI for unsigned builds and tests.
- Harden the compatibility shell's URL and data-clearing policies.

Exit evidence: clean clone builds both targets; contract fixtures pass; no source secret scan findings.

### Milestone 1 — Secure workspace foundation

- Workspace onboarding and explicit local/private/hosted labels.
- Keychain credential storage, scoped transport, local encrypted persistence, audit schema.
- Offline, timeout, certificate, and recovery UX.

Exit evidence: real private endpoint connection, restart persistence, deletion/export, cross-workspace isolation, and egress-deny tests.

### Milestone 2 — Usable native app

- One complete chat workflow on both platforms.
- Hermes read-only sessions plus approval/denial.
- Read-only War Room dashboard.

Exit evidence: physical iPhone and packaged Mac complete authenticated workflows against current private services with provenance and audit records.

### Milestone 3 — Platform depth

- iOS share-to-draft and App Intent.
- macOS sidebar, commands, and Spotlight experience.
- Read-only workspace browser; memories and insights backed by local stores.

Exit evidence: accessibility, locked-device, relaunch, network interruption, and workspace boundary suites pass.

### Milestone 4 — Distribution

- Privacy manifest, support/privacy/security docs, SBOM, signed provenance.
- TestFlight upload/install and notarized/stapled universal macOS DMG.
- Clean-device, upgrade, rollback, sign-out/purge, and offline smoke tests.

Exit evidence: App Store Connect processing succeeds, Gatekeeper accepts the DMG, and independent release checklist is signed off.

## Definition of done

“iOS and macOS app complete” means both apps perform the agreed private chat, Hermes review, and War Room workflows against current services; protect and delete local data as documented; pass automated and physical-device tests; and have verified TestFlight/notarized distribution evidence. A compiling target, hosted web page, screenshot, listener, DMG file, or unit-test pass alone is not sufficient.

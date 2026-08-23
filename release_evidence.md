# Release Evidence

## 2026-08-23 post-streaming main archive and TestFlight retry

- Source: pushed `main` at `42004f6` with the concrete Hermes URLSession stream, app live review, rollback-anchored audit ledger, pinned release tooling, and reconciled documentation.
- Fresh archive/export: `build/ios-42004f6/ThoxWarRoom.xcarchive` and `build/ios-42004f6/export/ThoxWarRoom.ipa`.
- Signature: `Apple Distribution: THOX AI LLC (DVJ6Z5343U)`; bundle `ai.thox.warroom`; TeamIdentifier `DVJ6Z5343U`; strict deep verification passed.
- Provisioning: `iOS Team Store Provisioning Profile: ai.thox.warroom`; application identifier `DVJ6Z5343U.ai.thox.warroom`; `beta-reports-active=true`; `get-task-allow=false`.
- IPA SHA-256: `5f4cfa753ce5e397393fb8efb02b17363b5ce754d832bbb1d12a2dafb2ed8110`.
- TestFlight upload was attempted with the externally supplied THOX AI LLC App Store Connect API key and rejected before transfer: `Cannot determine the Apple ID from Bundle ID 'ai.thox.warroom' and platform 'IOS'. (19)` followed by `ExitFailure (31)`.
- Remaining Apple-side gate: authenticate an App Store Connect owner/admin website session, create the iOS app record for `ai.thox.warroom`, then retry this exact IPA upload and verify processing/install.

## 2026-08-23 app-wired streaming and rollback-anchor wave

- Source commits: `1924f48` (incremental URLSession Hermes transport), `7f75424` (app-wired live read-only run review), `f07e037` (device-only Keychain audit head anchor), and `c79c3f5` (pinned XcodeGen release scripts).
- Hermes live review now concurrently loads run status and incremental SSE events. The Apple transport uses an ephemeral cookie-free/cache-free session, exact-origin redirect enforcement, bounded queued delivery, send-time bearer validation, and task/session cancellation. The app retains the newest 200 verified events and maps explicit complete/error/cancel/terminal states.
- The encrypted audit ledger now stores a fixed-width version/count/head-digest anchor as `WhenUnlockedThisDeviceOnly`. Existing ciphertext with a missing/invalid anchor, rollback, tail truncation, or divergent prefix fails closed; authenticated ciphertext ahead after an interrupted anchor update recovers forward. Cross-instance/process CAS, retention/export, and mutation wiring remain open.
- Validation: 136/136 package tests passed with warnings-as-errors; 63/63 integrated macOS app tests passed; deterministic XcodeGen/assets/privacy checks and the generic iOS Simulator test build passed through `./scripts/ci_unsigned.sh`.
- Both release scripts bootstrap repository-pinned checksum-verified XcodeGen 2.46.0. A credential-free unsigned/non-notarized macOS DMG packaging smoke test passed; this is not Developer ID or Gatekeeper release evidence.
- This source wave is newer than the signed IPA below. A fresh distribution-signed archive/export and upload retry are required before any TestFlight claim.

## 2026-08-23 fresh main archive and TestFlight retry

- Source: pushed `main` at `7cccff895f2cf1b8e327f7f149654d83352120d1`.
- Fresh archive/export: `build/ios-7cccff8/ThoxWarRoom.xcarchive` and `build/ios-7cccff8/export/ThoxWarRoom.ipa`.
- Signature: `Apple Distribution: THOX AI LLC (DVJ6Z5343U)`; bundle `ai.thox.warroom`; TeamIdentifier `DVJ6Z5343U`; strict deep verification passed.
- Provisioning: `iOS Team Store Provisioning Profile: ai.thox.warroom`; application identifier `DVJ6Z5343U.ai.thox.warroom`; `beta-reports-active=true`; `get-task-allow=false`.
- IPA SHA-256: `ef47a295c4bfeb43625f05141da7000afd37aa3989c9fce90ebe881ebb5141c3`.
- TestFlight upload was attempted with the externally supplied THOX AI LLC App Store Connect API key and rejected before transfer: `Cannot determine the Apple ID from Bundle ID 'ai.thox.warroom' and platform 'IOS'. (19)` followed by `ExitFailure (31)`.
- Apple documents that new App Store Connect app records cannot be created through its API. The record must be created on the website; the in-app browser reached Apple sign-in but has no authenticated owner session.
- Remote GitHub run `32646054643` for `7cccff8` had one job with zero steps and the exact annotation `The job was not started because your account is locked due to a billing issue.`

## 2026-08-23 contract/audit/streaming wave

- `WarRoomAppleInfrastructure` now supplies a concrete encrypted durable-audit store: workspace-scoped AES-256-GCM ciphertext, canonical redaction revalidation, actor-serialized ordered append, internal SHA-256 chain, idempotent IDs, bounded capacity/pages, time filtering, and digest-bound cursors.
- This is not rollback-resistant audit evidence: no external/Keychain monotonic head anchor exists, valid whole-ledger rollback/tail truncation is undetected, separate store instances can race, and retention/export/app mutation wiring remain open.
- `WarRoomHermes` now supplies a transport-neutral incremental event client with exact captured routing, bounded fragmented SSE parsing, cancellation, credential forwarding, and cross-run rejection. The app remains buffered; there is no concrete Apple streaming transport, reconnect/cursor behavior, or live provider proof.
- `WarRoomOpenWebUI` now has an executable fail-closed authenticated-chat evidence gate plus sanitized unauthenticated route-boundary fixture. Chat, streaming, and citation capabilities remain disabled; no DTO or traffic shape was guessed.
- Local validation: 119/119 package tests passed with warnings-as-errors. `CI_DERIVED_DATA=build/ci-wave2 ./scripts/ci_unsigned.sh` passed deterministic XcodeGen/assets, privacy checks, integrated macOS tests, and generic iOS Simulator test build.
- This validation occurred after the previously signed IPA, so a fresh signed archive/upload is required for the new source revision.

Evidence is recorded per platform and must not be generalized across lanes.

## 2026-08-23 encrypted workspace-profile integration

- Source commit: `99c802c` on local `main`, based on Core persistence seams `2263542`/`0c5efc5` and Apple encrypted-store foundation `a28af22`.
- Workspace profile payloads are AES-256-GCM encrypted with HKDF-SHA256 purpose keys; associated data binds workspace, collection, record, algorithm, key reference, and canonical timestamps.
- Per-workspace 256-bit master keys are non-synchronizing `WhenUnlockedThisDeviceOnly` Keychain items. Normal sealing cannot create a missing key over existing ciphertext.
- Ciphertext persistence uses bounded reads, atomic writes, private permissions, backup exclusion, symlink rejection, and complete iOS file protection. The iOS target also declares `com.apple.developer.default-data-protection = NSFileProtectionComplete`.
- App integration stores only provider ID and canonical validated profile fields, reconstructs capabilities from current trusted code, and revalidates endpoint/boundary/provider policy after decryption.
- Legacy plaintext preferences are removed only after encrypted write/read-back and active-selector persistence succeed. Credential deletion precedes profile cryptographic erasure, and interrupted ciphertext cleanup is retryable from the retained selector.
- Secret-free CI passed deterministic XcodeGen/assets/privacy checks, 106 standalone package tests with warnings as errors, 61 integrated macOS app tests, and the generic iOS Simulator app/test build.
- This is source, local-test, and simulator-build evidence. Physical locked-device behavior, rollback anchoring, HMAC-obscured routing indexes, encrypted chat/document history, app-wired audit policy, and a fresh signed/TestFlight artifact remain separate gates.

## 2026-08-23 encrypted-storage iOS archive and TestFlight attempt

- Source: pushed `main` at `df79fdc7980b8c4af6140b2a3cbcf64a227e6047`.
- App Store Connect API credential structure validation succeeded with the externally supplied key; no private key or bearer token was copied into the repository or logs.
- Release archive and App Store export succeeded at `build/ios-encrypted/ThoxWarRoom.xcarchive` and `build/ios-encrypted/export/ThoxWarRoom.ipa`.
- Exported signature: `Apple Distribution: THOX AI LLC (DVJ6Z5343U)`; identifier `ai.thox.warroom`; TeamIdentifier `DVJ6Z5343U`; strict deep signature verification passed.
- Provisioning: `iOS Team Store Provisioning Profile: ai.thox.warroom`; application identifier `DVJ6Z5343U.ai.thox.warroom`; `beta-reports-active=true`; `get-task-allow=false`.
- Exported entitlements include `com.apple.developer.default-data-protection=NSFileProtectionComplete`.
- IPA SHA-256: `43aa201ff1aacf6bd07d8986c14f9171070d99d38fc00db0bf58b37dfed22f65`.
- TestFlight upload was attempted and rejected before transfer with exact App Store Connect error: `Cannot determine the Apple ID from Bundle ID 'ai.thox.warroom' and platform 'IOS'. (19)` followed by `ExitFailure (31)`.
- Remaining owner gate: create the iOS App Store Connect app record for bundle `ai.thox.warroom`, then rerun this exact upload, wait for processing, install through TestFlight, and complete physical-device encrypted-storage/auth/relaunch checks.

## 2026-08-23 Apple privacy manifest validation

- Source release commit: `1056d60` on `main`.
- `App/PrivacyInfo.xcprivacy` is a valid property list bundled into both generated app targets.
- Current declarations: tracking disabled, no tracking domains, no developer/SDK data collection, and `NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1` for the app-only active-workspace selector and legacy migration.
- Source audit found direct required-reason API usage only through `UserDefaults`; credentials remain in non-synchronizing device-only Keychain storage and are not declared as collected by THOX.
- Independent review found that the legacy persistent `webui.thox.ai` WebView could not support the empty collection declaration without verified server-retention and embedded-domain evidence. Its user-facing route is now feature-disabled; native operator-configured provider surfaces remain available.
- Secret-free CI validates the source manifest and its Apple-required placement at the iOS app-bundle root and macOS `Contents/Resources` path.
- Full local CI passed: 77 standalone package tests, 58 integrated macOS app tests, and the generic iOS Simulator app/test build.
- This evidence does not replace App Store Connect privacy answers, an in-app/privacy-policy URL, review approval, TestFlight processing, or a fresh review if SDKs, telemetry, storage, or data ownership change.
- GitHub Actions run `32642947224` for `1056d60` failed before every step; its job has zero steps and the exact annotation `The job was not started because your account is locked due to a billing issue.` Local validation below is therefore not upgraded to remote-CI evidence.

## 2026-08-23 native provider and War Room integration with signed iOS export

- Source: release commit `1056d60` plus this evidence-only follow-up.
- Secret-free CI: passed deterministic XcodeGen/assets, 77 standalone package tests with warnings as errors, 58 integrated macOS app tests, and generic iOS Simulator app/test build.
- GitHub Actions run `32641564386` for `fcd62e9` failed before every step; its only job has zero steps and the exact annotation `The job was not started because your account is locked due to a billing issue.` This is an account/remote-CI blocker, not source-test evidence.
- Native slice: explicit Open WebUI/Hermes/MeshStack selection; provider-specific endpoint policy; Open WebUI credential/model catalog; credential-gated read-only buffered Hermes run review; credential- and canonical-MeshID-gated read-only War Room dashboard with partial results, freshness, and provenance.
- Credential lifecycle: workspace-scoped non-synchronizing Keychain items; workspace deletion removes the credential before metadata and preserves metadata when secure deletion fails.
- iOS archive/export: succeeded with Xcode 26.5 and XcodeGen 2.46.0.
- IPA signature: `Apple Distribution: THOX AI LLC (DVJ6Z5343U)`; bundle `ai.thox.warroom`; team `DVJ6Z5343U`.
- Provisioning: `iOS Team Store Provisioning Profile: ai.thox.warroom`.
- Privacy manifest: validated in the signed archive and exported IPA at the iOS bundle root.
- IPA SHA-256: `7e946bc76564b635a428691e1ebb5754acd60889743cc9145cd14aae46f956a8`.
- App Store Connect lookup authenticated with the externally supplied API key and returned zero app records for bundle `ai.thox.warroom`.
- Upload: not retried because no App Store Connect app record exists; an upload cannot attach to TestFlight until the website-only record is created.
- Remaining iOS gate: create the app record, upload, wait for processing, install from TestFlight on a physical iPhone, and complete authenticated/relaunch checks.

The API private key, generated JWT, provider credentials, and run identifiers were not copied into the repository or evidence output.

## 2026-08-23 iOS archive/export attempt

- Source: local `main` through `e2404cb` plus documentation-only working changes.
- Toolchain: Xcode 26.5, XcodeGen 2.46.0.
- Target: `ThoxWarRoom iOS`, Release, generic iOS device.
- Team: `DVJ6Z5343U` (THOX AI LLC).
- Bundle ID: `ai.thox.warroom`.
- App icon validation: passed metadata, dimensions, assignment, opacity, and direct `actool` compilation checks.
- Archive: succeeded with automatic provisioning.
- Export: succeeded.
- IPA code signature: `Apple Distribution: THOX AI LLC (DVJ6Z5343U)`; `codesign --verify --deep --strict` passed.
- Provisioning: `iOS Team Store Provisioning Profile: ai.thox.warroom`; application identifier `DVJ6Z5343U.ai.thox.warroom`.
- IPA SHA-256: `b1020e2611e86678c3647a5f0cdf882e92a8e6dd478141607b92228f4f2be267`.
- Upload: failed before transfer with `Cannot determine the Apple ID from Bundle ID 'ai.thox.warroom' and platform 'IOS'. (19)`.
- App Store Connect API verification: the universal bundle ID exists, but the account contains zero app records for `ai.thox.warroom`.
- Remaining gate: create the App Store Connect app record in Apple's website, repeat upload, wait for processing, install from TestFlight on a physical iPhone, and complete authenticated/relaunch checks.

No API private key or bearer token is stored in this repository or this evidence file.

## 2026-08-23 native foundation integration

- `WarRoomCore`: 16/16 tests passed.
- `WarRoomAppleInfrastructure`: 14/14 tests passed with warnings as errors.
- `WarRoomOpenWebUI`: 14/14 offline tests passed with warnings as errors.
- `WarRoomHermes`: 17/17 offline tests passed with warnings as errors.
- Integrated macOS app: 21/21 tests passed with all four packages linked.
- Generic iOS Simulator app/test build: succeeded with all four packages linked.
- iPhone 17 Pro Test simulator: app installed and launched; native `Private workspace` empty state rendered.

This is source, simulator, and local build evidence. It is not authenticated
private-provider, physical-device, TestFlight, notarization, or release evidence.

## 2026-08-23 macOS unsigned packaging validation

- Target: `ThoxWarRoom macOS`, Release, arm64.
- Unsigned build and DMG packaging: succeeded.
- `hdiutil verify`: valid.
- DMG SHA-256: `b6a4969b9c165fe4a07e2a4ccbc1c69aa1673b19ebd9e670e333d412a34fbaa6`.
- Developer ID/notarization run: not executed.
- Exact blocker: `ERROR: no Developer ID Application signing identity for team DVJ6Z5343U is available in the Keychain`.
- Remaining gate: install the THOX Developer ID Application identity, configure a Keychain notary profile, run the release mode, and retain final `codesign`, `stapler`, `spctl`, mounted-app, checksum, and clean-device evidence.

The unsigned DMG is build evidence only and is not a distributable release.

## 2026-08-23 native CI activation

- Runs `32638587436`, `32638619138`, `32638691508`, and post-foundation run `32639512911` each failed before executing any step.
- GitHub's check annotation states: `The job was not started because your account is locked due to a billing issue.`
- The intended `macos-26` runner was retained because none of the jobs reached runner selection or source execution.
- Local `./scripts/bootstrap.sh` passed the same secret-free lane at the workspace-foundation revision: 16 Shared Core tests, 21 integrated macOS tests, deterministic generation/assets, and a generic iOS Simulator test build. GitHub billing must be unlocked and a remote run must pass before WR-010 is considered implemented remotely.

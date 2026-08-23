# Release Evidence

## 2026-08-23 multi-workspace iOS and macOS TestFlight build 5 delivery

- Exact pushed source: `2c299efa79caad9e08aa6f4fa41e349094f9e237` on `main`. The source adds encrypted multi-workspace enumeration, verified explicit selection, isolated credential-first deletion, and verified deterministic fallback selection (`f2e547b`), then advances both Apple targets to 4.2.0 (5) with current architecture/security/release documentation (`2c299ef`).
- Pre-release validation: tracked-source secret scan, deterministic SPDX generation, deterministic XcodeGen/assets/privacy validation, 7 Python tests, 214 standalone Swift package tests with warnings as errors, 97 integrated macOS tests, and the generic arm64/x86_64 iOS Simulator test build passed. The focused encrypted-workspace suite passed 13/13 tests. The machine's LaunchServices registration child hung during the macOS Xcode stages; only the exact `lsregister` child for each generated ThoxWarRoom app was terminated, after which Xcode recorded registration as skipped and completed successfully.
- iOS 4.2.0 (5): build/delivery ID `dbc143d9-5881-4bb9-91ca-2ffb01d70fce`; IPA `build/ios-2c299ef/export/ThoxWarRoom.ipa`; SHA-256 `5adb484dcb5a2c2ef77fd9b905da05f75923bb7196e202c70fb1c84bca6fce30`. Archive, export, embedded privacy-manifest validation, and upload completed without errors.
- macOS 4.2.0 (5): build/delivery ID `dbdd4881-83e4-4507-a823-faa9b38e86e9`; package `build/macos-appstore-2c299ef/export/ThoxWarRoom.pkg`; SHA-256 `ece17e50e2128c8dbd672c16e6c7a95218bccd9507b88ad8fb4672d32ecc4677`. The archived app passed strict code-sign, sandbox/no-debug, privacy-manifest, and universal x86_64/arm64 checks; the exported installer passed Apple certificate-chain validation and uploaded without errors.
- Shared source-revision SPDX SHA-256: `ce5e75764239359e2f80c99abc8227e4f7feb53d5da921d6e262f5ea0dbea875`.
- App Store Connect processing: both build 5 records are `VALID`, `IN_BETA_TESTING`, and `READY_FOR_BETA_SUBMISSION`. Adding both build IDs to internal group `312308e3-a3d6-4dbf-bc08-c7c1be6081e5` returned HTTP 204.
- Xcode/computer-use evidence remains distinct: the exact `ThoxWarRoom.xcodeproj` was opened and showed the native iOS scheme ready before this candidate. After assignment, a fresh App Store Connect UI reload showed `THOX AI LLC Internal` with 4 testers and 8 builds, up from 6; archive/export/upload and API processing evidence above prove the build-5 release lane.
- Physical evidence remains separate. App Store Connect reports iOS build 4 installed on an iPad, not build 5 runtime. The connected iPhone remains on build 3, and macOS build 4 was visible but uninstalled before this upload. No direct build-5 launch, authentication, relaunch, locked-device, or removal smoke is claimed.
- A proposed URLSession DNS/IP-pinning change was excluded after a credential-free live probe proved that replacing an HTTPS hostname with its IP breaks virtual-host TLS/SNI before delegate trust evaluation can repair it. DNS-bound transport remains an explicit gate and requires a reviewed connection primitive that preserves logical-host SNI while binding an approved peer address.

## 2026-08-23 Audit Center iOS and macOS TestFlight build 4 delivery

- Exact pushed source: `4518091bbaf2eff93b8512fb54148b6b0ccf7194` on `main`. Source changes include read-only Hermes operation reconciliation (`455b094`), encrypted workspace audit-policy persistence (`278493f`), native cross-platform Audit Center (`7fcb169`), and fail-closed stale-policy handling (`7422cd8`).
- Pre-release validation: deterministic Xcode project/assets and privacy manifest checks, tracked-source secret scan, deterministic SPDX generation, 7 Python tests, 214 standalone Swift package tests with warnings as errors, 95 integrated macOS tests, and a generic arm64/x86_64 iOS Simulator test build all passed. The machine's LaunchServices registration child hung during the macOS Xcode stages; only the exact `lsregister` child for each generated ThoxWarRoom app was terminated, after which Xcode recorded registration as skipped and completed successfully.
- iOS 4.2.0 (4): delivery/build ID `2a89be7a-9cc6-455a-849d-c64f2ba6f42f`; IPA `build/ios-4518091/export/ThoxWarRoom.ipa`; SHA-256 `79e4ed23790b8808e9a4dab2b5bf42905b9076d8577cc7437471fc0ba4848709`. Strict code-sign verification passed; the exported app has `beta-reports-active=true`, `get-task-allow=false`, and `NSFileProtectionComplete`.
- macOS 4.2.0 (4): delivery/build ID `4f0c7431-3970-4be4-ba97-3bf2c5919e12`; package `build/macos-appstore-4518091/export/ThoxWarRoom.pkg`; SHA-256 `995f6bac4d9324c9c5b3a553c4611d1e8098a49cbb67e58665459a26229d6bef`. Archive strict code-sign verification and installer certificate-chain validation passed; the app binary is universal arm64/x86_64 and the App Store sandbox/no-debug gates passed.
- Both platform artifacts embed source-revision SPDX SBOM SHA-256 `fe2bc450078bd6bedae4079461d6e229460a57b830281a748b70cb459907a4a8`.
- App Store Connect processed both records to `VALID`, `IN_BETA_TESTING`, and external `READY_FOR_BETA_SUBMISSION`. Both build IDs were assigned to `THOX AI LLC Internal` (`312308e3-a3d6-4dbf-bc08-c7c1be6081e5`), whose related-build count is now six (iOS/macOS builds 2, 3, and 4).
- This proves signed upload, Apple processing, and internal-group assignment. It does not prove invitation acceptance, physical iPhone/Mac TestFlight install/launch, authenticated provider workflows, or Developer ID/notarized direct macOS distribution.

## 2026-08-23 hardened iOS and macOS TestFlight build 3 delivery

- Application source: pushed `main` at `0ce9cd1d27ba3c69b2be6fbfdac15abd221778fd` before both signed builds. The worktree and `origin/main` matched that SHA.
- Included source hardening: fail-closed Hermes human mutation review (`ed85d25`), strict offline OpenWebUI contract evidence qualification (`2471338`), and encrypted durable operation replay/reconciliation with Keychain-committed rollback/deletion detection (`c7e0d66`). Production mutation transport and native chat remain disabled pending verified live contracts.
- Integrated release gate: 193/193 standalone Swift package tests, 80/80 integrated macOS app tests, and 7/7 Python release/security tests passed; deterministic XcodeGen/assets/privacy checks and the generic iOS Simulator test build also passed. A stale SwiftPM runner/toolchain link was eliminated by regenerating XCTest-only package runners. Local LaunchServices registration hung during macOS test/archive finalization; terminating only that helper caused Xcode to record registration as skipped and complete successfully.
- iOS archive/export/upload: `build/ios-0ce9cd1/ThoxWarRoom.xcarchive` and `build/ios-0ce9cd1/export/ThoxWarRoom.ipa`; IPA SHA-256 `7e5890eeb7e559e7b102eaa7537aadc58dce84d8739375b41c1c53a7b140780c`; delivery/build ID `59641301-6e5c-4f15-aa5f-d4456a0c7f60`.
- Native macOS App Store archive/export/upload: `build/macos-appstore-0ce9cd1/ThoxWarRoom.xcarchive` and `build/macos-appstore-0ce9cd1/export/ThoxWarRoom.pkg`; package SHA-256 `211414161be93b9cad50d79fe6f39c760f63ae524cbf29bd0780102866d32ce4`; delivery/build ID `db0ba014-ba86-495e-b816-7e7104b34deb`. The first transfer entered a repeated server checksum-retry loop and was terminated; a clean retry of the exact same verified package succeeded.
- Both lanes generated the same revision-bound SPDX document, SHA-256 `309dbdf2d548d68aaac243f76665a5adf47a06e09dcc41ce0f2811f1faef6c32`.
- Both version 4.2.0 build 3 records reached Apple `VALID`, `IN_BETA_TESTING`, and external `READY_FOR_BETA_SUBMISSION`. The source Info.plists contained `ITSAppUsesNonExemptEncryption=false`; no manual export-compliance repair was required.
- Both build 3 IDs were assigned to `THOX AI LLC Internal` (`312308e3-a3d6-4dbf-bc08-c7c1be6081e5`). App Store Connect returned all four build 2/3 platform records in that group. Tommy Xaypanya (`tommy@thox.ai`) remains the single tester with state `INVITED`.
- Remaining evidence gates: invitation acceptance and physical iPhone/Mac TestFlight install/launch are not observed. Native authenticated chat lacks all nine sanctioned contract captures; production Hermes mutation composition lacks verified authorization/live contract evidence. Direct Developer ID/notarized DMG distribution remains separate.

## 2026-08-23 successful iOS and macOS TestFlight delivery

- Application source: pushed `main` at `23650a9301595c68f2b51a996c3fae4bbf53dbba` before both signed builds. The worktree and `origin/main` matched that SHA.
- App Store Connect record: created under THOX AI LLC for name `ThoxWarRoom`, bundle `ai.thox.warroom`, SKU `THOXWARROOM-APPLE-2026`, primary locale `en-US`, and both iOS/macOS platforms. App ID: `6804445585`.
- Integrated release gate: 174/174 standalone Swift package tests, 73/73 integrated macOS app tests, and 7/7 Python release/security tests passed; deterministic XcodeGen/assets/privacy checks and the generic iOS Simulator test build also passed.
- iOS archive/export/upload: `build/ios-23650a9/ThoxWarRoom.xcarchive` and `build/ios-23650a9/export/ThoxWarRoom.ipa`; IPA SHA-256 `85230cf29e6bdd490880af09ec36b759e18987cf4288de4db5efa8a32db0ba9e`; delivery/build ID `42c44ca0-c1e1-4e59-9017-3f2181ad14b3`.
- Native macOS App Store archive/export/upload: `build/macos-appstore-23650a9/ThoxWarRoom.xcarchive` and `build/macos-appstore-23650a9/export/ThoxWarRoom.pkg`; package SHA-256 `822a1519956b0c57e1956a52227cad9f674cd5059a59753f5daf7b06e2ce75af`; delivery/build ID `5d367041-21a3-4fa5-9951-541f35f12cb9`.
- Both lanes generated the same revision-bound SPDX document, SHA-256 `af68dd00b070509b2981ec16d0bfae81050a875e8b348ab3ed87357b190d9d34`.
- App Store Connect processing: both build 2 artifacts for version 4.2.0 reached `VALID`. After recording `usesNonExemptEncryption=false` for the app's Apple CryptoKit/OS-provided encryption path, both reached `READY_FOR_BETA_TESTING` internally and `READY_FOR_BETA_SUBMISSION` externally.
- Internal distribution: group `THOX AI LLC Internal` (`312308e3-a3d6-4dbf-bc08-c7c1be6081e5`) contains both builds. The THOX admin `tommy@thox.ai` is an invited internal tester; App Store Connect shows 1 tester and 2 builds.
- Remaining evidence gates: invitation acceptance and physical iPhone/Mac TestFlight install/launch are not yet observed. External testing still requires beta review submission. Direct Developer ID/notarized DMG distribution remains a separate uncompleted lane.
- The external API private key and generated bearer tokens were not copied into source, documentation, or retained command output.

## 2026-08-23 final application-source Apple artifacts

- Application source and reconciled product documentation: pushed `main` at `73a5fff` before this evidence-only append.
- iOS archive/export: `build/ios-73a5fff/ThoxWarRoom.xcarchive` and `build/ios-73a5fff/export/ThoxWarRoom.ipa`. Apple Distribution signature, bundle `ai.thox.warroom`, TeamIdentifier `DVJ6Z5343U`, strict deep verification, App Store provisioning, `beta-reports-active=true`, and `get-task-allow=false` were verified. IPA SHA-256: `747163f9fb4dac3e2097b6b06e4b7816899851ce59619ae9bc9b225aa4a9cd22`.
- Native macOS App Store archive/export: `build/macos-appstore-73a5fff/ThoxWarRoom.xcarchive` and `build/macos-appstore-73a5fff/export/ThoxWarRoom.pkg`. The embedded app is Apple Distribution signed for team `DVJ6Z5343U`; strict deep verification passed; app sandbox, user-selected read-only files, and network client are present; `get-task-allow` is absent. The installer uses the THOX `3rd Party Mac Developer Installer` certificate. Package SHA-256: `3a679fe3526bb1a030ee9924daecaf0ef05585f339814ef11d91b179bcfa4f9b`.
- Both artifact lanes generated the same revision-bound SPDX file, SHA-256 `6bbdef163ce0d28ce5109daa49e6529e00f425ff59f96431dc9ffbe47c7f531f`.
- Final iOS and macOS uploads were attempted with the externally supplied THOX API key. Apple rejected both before transfer because no matching app record exists: platform `IOS` and platform `MAC_OS` each returned `Cannot determine the Apple ID from Bundle ID 'ai.thox.warroom' ... (19)` followed by `ExitFailure (31)`.
- Required owner action remains: authenticate an Account Holder/Admin/App Manager website session, confirm agreements, create the shared iOS/macOS app record, and then retry these exact artifacts. Upload, processing, TestFlight installation, and physical-device behavior remain unproven.

## 2026-08-23 persistence, browser, SBOM, and macOS TestFlight wave

- Source implementation through `5c487fe`: cooperative cross-process audit transaction serialization (`c3a2947`), resumable Keychain deletion journal (`c5a6810`), confined local workspace browser (`5c487fe`), deterministic SPDX generation (`b768b5d`/`eea9e2d`), and macOS App Store/TestFlight tooling (`0047611`).
- Integrated local validation: 155/155 standalone Swift package tests and 71/71 integrated macOS app tests passed with warnings-as-errors; three Python SPDX tests passed; deterministic project/assets/privacy checks and the generic iOS Simulator test build passed through `CI_DERIVED_DATA=build/ci-wave4 ./scripts/ci_unsigned.sh`.
- Mac App Store archive/export succeeded at `build/macos-appstore-5c487fe/ThoxWarRoom.xcarchive` and `build/macos-appstore-5c487fe/export/ThoxWarRoom.pkg` using the THOX team and repository-pinned XcodeGen 2.46.0.
- Exported app signature: `Apple Distribution: THOX AI LLC (DVJ6Z5343U)`; identifier `ai.thox.warroom`; TeamIdentifier `DVJ6Z5343U`; strict deep verification passed. Entitlements include app sandbox, read-only user-selected files, network client, application identifier, and team identifier; `get-task-allow` is absent.
- Installer signature: `3rd Party Mac Developer Installer: THOX AI LLC (DVJ6Z5343U)`. Package SHA-256: `52b271cc7e6b79d80bd6db33d4b0413dceaae577ae746ff6581a4a6d8a2675de`.
- SPDX SHA-256: `4bcfd704e528dd0f7d3998fd4ef76e421453897d7b2730924dda9fce28f332ec`. It inventories the app plus five local Swift packages and fails closed if an unmodeled remote package declaration appears.
- macOS App Store Connect upload was attempted with the external THOX API key and rejected before transfer: `Cannot determine the Apple ID from Bundle ID 'ai.thox.warroom' and platform 'MAC_OS'. (19)` followed by `ExitFailure (31)`.
- Both this macOS package and the previously signed iOS IPA predate the final documentation commit. Rebuild both from the pushed final SHA after the shared iOS/macOS App Store Connect record exists.

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

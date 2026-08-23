# Release Evidence

Evidence is recorded per platform and must not be generalized across lanes.

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

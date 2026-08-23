# Release Evidence

Evidence is recorded per platform and must not be generalized across lanes.

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

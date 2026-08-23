# ThoxWarRoom

> Local-first native SwiftUI foundation for private THOX workspaces. One codebase, two targets: macOS 14+ (universal) and iOS 17+ (iPhone). Built for THOX AI LLC.

ThoxWarRoom now starts with native workspace onboarding. Users explicitly choose a local-device, private-network, or hosted boundary before any provider can be opened; hosted transfer requires separate consent. Endpoint/profile metadata is AES-256-GCM encrypted locally with workspace-scoped device-only Keychain keys; credentials remain separate in Keychain. The former Open WebUI shell remains compiled for migration compatibility but is not exposed while the hosted retention and App Store privacy contract are unverified.

> **Current scope:** v4.2 has the clean-room shared core, encrypted workspace-profile persistence, an encrypted durable-audit store seam, native provider selection, Open WebUI discovery/credential/model-catalog UI, a credential-gated read-only Hermes run review plus incremental event-stream seam, and a credential-gated read-only MeshStack War Room dashboard. Native authenticated chat, app-wired live Hermes streaming/actions, encrypted chat/document history, rollback-anchored audit policy, live private-service verification, and completed distribution remain unfinished. See the [Hermes completion audit](HERMES_COMPLETION_AUDIT.md), [current service contracts](docs/current_service_contracts.md), [MVP catalog](mvp_catalog.md), and [multi-team development queue](development_queue.md).

Current build, signing, upload, and blocker evidence is recorded in [release_evidence.md](release_evidence.md).

Both Apple targets bundle `App/PrivacyInfo.xcprivacy`. Local and release scripts validate its reviewed no-tracking/no-developer-collection declarations, the app-only UserDefaults reason, and platform-correct bundle placement. Re-audit the manifest before adding SDKs, telemetry, shared defaults, or developer-operated data collection.

## Targets

| Target | Platform | Min OS | UI framework | Web framework |
|---|---|---|---|---|
| `ThoxWarRoom macOS` | macOS 14+ | Universal | SwiftUI | Native onboarding + gated `WKWebView` compatibility |
| `ThoxWarRoom iOS`   | iOS 17+   | iPhone    | SwiftUI | Native onboarding + gated `WKWebView` compatibility |

Both targets share the same Swift sources in `App/` — platform-conditional via `#if os(macOS)` / `#if os(iOS)`. The bundle identifier is `ai.thox.warroom` for both. Apple Developer Team: `DVJ6Z5343U` (THOX AI LLC).

## Project layout

```
thoxwarroom/
├── project.yml                 # XcodeGen — single source of truth for the Xcode project
├── App/
│   ├── ThoxWarRoomApp.swift    # @main App, scene wiring, dark appearance
│   ├── ContentView.swift       # Root routing: onboarding or authorized compatibility surface
│   ├── WorkspaceOnboarding*.swift # Boundary selection, encrypted metadata lifecycle, and states
│   ├── EncryptedWorkspaceProfileRepository.swift # AES-GCM/Keychain profile composition
│   ├── HostedCompatibilityView.swift # Explicit exact-host WebView entry
│   ├── WebViewRepresentable.swift  # macOS NSViewRepresentable + iOS UIViewRepresentable
│   ├── ThoxWebViewModel.swift  # ObservableObject: load state, navigation policy
│   ├── ThoxTheme.swift         # THOX emerald accent + dark surfaces
│   ├── LoadingOverlay.swift    # Branded spinner + offline/Retry
│   ├── ThoxWarRoom.entitlements # macOS app sandbox + network client
│   └── ThoxWarRoom-iOS.entitlements # Complete default iOS file protection
├── Assets.xcassets/            # Xcode asset catalog (icons + accent color)
│   ├── AppIcon.appiconset/     # iOS universal icons
│   └── AppIcon-mac.appiconset/ # macOS icons
├── Resources/                  # Standalone AppIcon.icns (for productbuild/DMG fallback)
│   ├── AppIcon-master.png      # 1024x1024 master
│   ├── AppIcon.icns
│   └── AppIcon.appiconset/     # Loose iOS iconset (mirrored into Assets.xcassets)
├── Tests/
│   ├── ThoxWarRoomTests.swift  # Navigation policy + load state machine tests
│   └── WorkspaceOnboardingTests.swift # Boundary, consent, persistence, and gate tests
├── Packages/
│   ├── WarRoomCore/            # Endpoint, workspace, audit, credential/transport seams
│   ├── WarRoomAppleInfrastructure/ # Keychain, AES-GCM file store, scoped URLSession
│   ├── WarRoomOpenWebUI/       # Bounded discovery + provisional model catalog
│   ├── WarRoomHermes/          # Run/status/SSE/approval/stop contracts
│   └── WarRoomMesh/            # Read-only devices/topology/events contracts
├── scripts/
│   ├── gen_appiconset.py       # Regenerate THOX-green chip-mark icons
│   ├── build_macos.sh          # Developer ID signed, notarized, stapled macOS DMG
│   ├── build_ios.sh            # Archive + TestFlight upload
│   ├── bootstrap.sh            # Clean-clone tool bootstrap + unsigned CI
│   ├── bootstrap_xcodegen.sh   # Pinned, checksum-verified local XcodeGen
│   ├── ci_unsigned.sh          # Secret-free macOS tests + iOS build
│   ├── ci.sh                   # Extended local packaging CI
│   └── smoke_test.sh           # E2E launch + persistent login check
├── .env.example                # APPLE_ID / APPLE_PASSWORD placeholders
├── AGENTS.md                   # Project conventions for AI workers
└── README.md
```

## Build & run

```bash
# 1) Clean-clone bootstrap + unsigned build/test (no global XcodeGen install)
./scripts/bootstrap.sh

# 2) Build a release-ready Developer ID + notarized macOS DMG.
# NOTARY_PROFILE must already exist in the login Keychain.
NOTARY_PROFILE=THOX_NOTARY ./scripts/build_macos.sh
# Output: build/macos/ThoxWarRoom-Release-arm64.dmg

# Credential-free local packaging check (explicitly not release-ready)
SIGNING_MODE=unsigned SKIP_NOTARIZE=1 ./scripts/build_macos.sh

# 3) Build the iOS app + upload to TestFlight
APPLE_ID=you@apple.com APPLE_PASSWORD=app-specific-pw \
    ./scripts/build_ios.sh
# Output: build/ios/export/ThoxWarRoom.ipa
```

### Launch the macOS app

```bash
open build/macos/derived/Build/Products/Release/ThoxWarRoom.app
```

The app opens native workspace onboarding. The legacy `https://webui.thox.ai` compatibility WebView is disabled pending a verified hosted retention and App Store privacy contract; configured Open WebUI profiles use the native connection surface.

## Behavior

- **Explicit workspace boundary** — local device is the default; private network and hosted service are separately labeled. No provider is contacted while saving metadata.
- **Hosted consent and disabled compatibility boundary** — hosted configuration requires affirmative data-transfer consent. The legacy WebView additionally remains feature-disabled until THOX verifies server retention, embedded domains, and matching App Store privacy declarations.
- **Encrypted workspace profiles** — profile payloads are sealed with AES-256-GCM using HKDF-derived purpose keys and workspace-scoped, non-synchronizing `WhenUnlockedThisDeviceOnly` Keychain master keys. Ciphertext writes are atomic, bounded, private, excluded from backup, and use complete iOS file protection. `UserDefaults` retains only the active workspace UUID and legacy migration evidence until encrypted read-back succeeds.
- **Workspace-scoped credentials and deletion** — Open WebUI and Hermes credentials are rejected in URLs, entered through privacy-sensitive native fields, and stored separately in Keychain. Workspace removal must delete the provider credential before cryptographic profile erasure; credential failure preserves the workspace for retry.
- **Native provider surfaces** — Open WebUI exposes bounded public discovery and a protected model catalog; its executable evidence gate keeps native chat/stream/citation capabilities disabled until authenticated contracts are captured. Hermes exposes credential-gated read-only run status and buffered events, plus a transport-neutral bounded incremental SSE client. The app does not yet claim app-wired live streaming or audited approval controls.
- **Encrypted durable audit seam** — workspace-scoped AES-GCM ledgers revalidate redaction, serialize appends within one actor, chain ordered entries, bind cursors to workspace/digest, and bound capacity/pages. Whole-ledger rollback/tail truncation, cross-instance writers, retention/export, and app mutation wiring remain explicit gaps.
- **Read-only War Room** — MeshStack workspaces require a canonical operator-supplied mesh UUID and Keychain credential before loading bounded devices, topology, and events. The dashboard shows provenance, freshness, empty/offline/error states, and partial results; it exposes no pairing, deletion, token creation, or control-plane write.
- **Persistent session with explicit purge** — `WKWebViewConfiguration.websiteDataStore = .default()` keeps login data across relaunch. **Sign Out** requires confirmation, clears all WebKit website data in the app container, reports clearing/success/failure state, and reloads the canonical URL after success. This clears local session material; server-side token revocation is not yet verified.
- **Strict in-app policy** — only credential-free `https://webui.thox.ai` URLs on the default HTTPS port are allowed in the WebView. Host suffixes, HTTP, custom schemes, embedded credentials, and non-default ports are never allowed in-app.
- **Safe external navigation** — credential-free, default-port HTTPS links open in the system browser only for an explicit `.linkActivated` action. Automatic redirects and script-driven off-domain navigations are cancelled. Allowed `target=_blank` links stay in the current WebView.
- **Loading state** — branded overlay (THOX emerald spinner + "Loading webui.thox.ai…") until `didFinish` fires.
- **Error state** — branded card with wifi-exclamation icon, error message, and a Retry button. Never a white screen — `didFail` / `didFailProvisionalNavigation` always route to the overlay.
- **Dark-mode-first** — `preferredColorScheme(.dark)` on both platforms + macOS `NSApp.appearance = .darkAqua` set on `applicationDidFinishLaunching`.

## Signing & distribution

### macOS

- Team: `DVJ6Z5343U` (THOX AI LLC)
- Release code signing: `Developer ID Application` with hardened runtime. The script rejects a release app carrying `com.apple.security.get-task-allow=true`.
- App Sandbox: enabled (`com.apple.security.app-sandbox=true`)
- Hardened runtime: enabled
- Network client: enabled (`com.apple.security.network.client=true`)
- Notarization: required by default through a `notarytool` Keychain profile named by `NOTARY_PROFILE`; credentials are never passed on the command line or stored in the repository.
- Packaging order: notarize/staple app → stage app → create/sign DMG → notarize/staple DMG → validate the final mounted app and DMG with `codesign`, `stapler`, and `spctl`.
- Local-only modes: `SIGNING_MODE=unsigned SKIP_NOTARIZE=1` or `SIGNING_MODE=adhoc SKIP_NOTARIZE=1`. These produce a checksum and verify DMG integrity but intentionally skip trust claims.
- Output DMG: `build/macos/ThoxWarRoom-Release-arm64.dmg`

### iOS

- Team: `DVJ6Z5343U` (THOX AI LLC)
- Code signing: Automatic, allows provisioning updates (`-allowProvisioningUpdates`)
- Bundle id: `ai.thox.warroom` (iPhone only, `TARGETED_DEVICE_FAMILY=1`)
- Minimum OS: iOS 17
- Upload: `xcrun altool --upload-app --type ios` (App Store Connect API key preferred, see `.env.example`)
- API-key variables: `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID`, and `ASC_API_KEY_P8`. The `.p8` stays outside the repository and is passed directly to Xcode provisioning and `altool`; neither it nor the locally generated JWT is logged.
- Credential-only check: `source .env && VALIDATE_CREDENTIALS_ONLY=1 ./scripts/build_ios.sh`

## Tests

```bash
xcodebuild \
    -project ThoxWarRoom.xcodeproj \
    -scheme "ThoxWarRoom macOS" \
    -destination "platform=macOS" \
    CODE_SIGNING_ALLOWED=NO \
    test
```

135 current tests cover 77 standalone package cases plus 58 integrated macOS app cases, including:

- Base URL is `https://webui.thox.ai`
- User-activated safe HTTPS off-domain URLs → external
- Automatic/scripted off-domain URLs → cancelled
- Unsafe schemes, credentials, ports, and missing URLs → cancelled
- Exact `webui.thox.ai` HTTPS origin and subpaths → in-app
- Initial state is `.idle`
- `didStart` / `didFinish` / `didFail` transitions
- Sticky error state (subsequent `didFinish` doesn't clobber a `.error`)
- Reload lifecycle (`isReloadPending` flips and acknowledges)
- `resetForRetry` arms a reload and lands in `.loading`
- Persistent-session clearing success/failure state, canonical reload, and non-sensitive errors
- Local/private/hosted boundary validation and explicit hosted consent
- Metadata round-trip, corrupt-state recovery, deletion, and credential rejection
- Exact-host compatibility availability; suffixes, ports, and paths remain denied
- Workspace-scoped, non-synchronizing Keychain behavior and typed failures
- Cookie/cache-free transport, exact-origin redirects, bounded bodies, and safe bearer handling
- Open WebUI discovery/model-contract decoding without live-network tests
- Hermes run routing, response correlation, buffered and live-byte bounded fragmented SSE parsing, canonical approvals, and cancellation
- Read-only Mesh device/topology/event decoding, mesh isolation, freshness, provenance, and bounds
- Provider selection, provider-specific port policies, legacy mapping, credential lifecycle deletion, and read-only Hermes UI state

## Design system

| Token | Value | Use |
|---|---|---|
| `ThoxTheme.accent` | `#05A451` | THOX emerald — primary action, spinner, brand mark |
| `ThoxTheme.background` | `#0C0E12` | App backdrop (matches OpenWebUI dark) |
| `ThoxTheme.surface` | `#161A20` | Card / overlay surface |
| `ThoxTheme.separator` | `white @ 8%` | Hairline borders |
| `ThoxTheme.primaryText` | `white` | Body |
| `ThoxTheme.secondaryText` | `#A6A6A6` | Captions / error detail |

The app icon is a THOX emerald rounded square with a stylized "chip" mark (3 dark horizontal slabs forming a T silhouette). `scripts/gen_appiconset.py` regenerates the full icon set from a single 1024×1024 master using Pillow + `iconutil`.

Generated icon PNGs, catalogs, and `.icns` output are intentionally ignored by
Git. Both Xcode app targets run `scripts/ensure_appiconsets.sh` before asset
compilation; it reuses valid generated catalogs or regenerates and validates
them with the existing deterministic generator. `scripts/bootstrap.sh` remains
the canonical clean-clone validation entry point and also verifies generation
drift.

## CI

`scripts/bootstrap.sh` is the clean-host entry point. It downloads XcodeGen
2.46.0 into the ignored `.tools/` directory, verifies the official release
archive SHA-256 before extraction, and runs `scripts/ci_unsigned.sh`. The
unsigned lane regenerates the Xcode project and icons twice to detect drift,
validates the asset catalogs, tests every standalone Swift package with warnings
as errors, runs the macOS unit tests, and builds the iOS app and test bundle for
a generic Simulator. It never reads signing secrets or
calls archive, export, upload, notarization, or release-package commands.

GitHub Actions runs this same lane for pull requests and pushes to `main` on a
`macos-26` runner with read-only repository permissions. The workflow contains
no signing or App Store credentials.

The extended local packaging CI remains available when release credentials and
packaging validation are intentionally in scope:

`scripts/ci.sh` runs:

1. Verify toolchain (`xcodebuild`, `xcrun`, `xcodegen`, `python3`, `iconutil`)
2. `xcodegen generate`
3. `python3 scripts/gen_appiconset.py`
4. `python3 scripts/validate_appiconsets.py`
5. Build for testing
6. Run macOS unit tests
7. Signed macOS build + DMG
8. iOS archive + TestFlight upload

Override via env vars: `SKIP_IOS_BUILD=1`, `SKIP_MACOS_BUILD=1`, `SKIP_NOTARIZE=1`, `SKIP_UPLOAD=1`.

## License

MIT — see [LICENSE](./LICENSE).

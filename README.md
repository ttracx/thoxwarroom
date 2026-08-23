# ThoxWarRoom

> Native SwiftUI wrapper for [webui.thox.ai](https://webui.thox.ai). One codebase, two targets: macOS 14+ (Apple Silicon) and iOS 17+ (iPhone). Built for THOX AI LLC.

ThoxWarRoom is a thin, branded shell that loads the THOX Open WebUI in a persistent `WKWebView`. Sign in once; the cookie store keeps you signed in across launches. A confirmed native sign-out control clears that persistent website data. Only safe, user-activated HTTPS links may open off-domain in the system browser. Dark-mode-first, THOX emerald chip-mark icon, native macOS titlebar and iOS navigation chrome.

> **Current scope:** v4.2 is a compatibility shell, not yet the full native War Room product that existed in the v4.1 Flutter history. See the [Hermes completion audit](HERMES_COMPLETION_AUDIT.md), [MVP catalog](mvp_catalog.md), and [multi-team development queue](development_queue.md) for the evidence-based native iOS/macOS delivery plan.

Current build, signing, upload, and blocker evidence is recorded in [release_evidence.md](release_evidence.md).

## Targets

| Target | Platform | Min OS | UI framework | Web framework |
|---|---|---|---|---|
| `ThoxWarRoom macOS` | macOS 14+ | Apple Silicon | SwiftUI | `WKWebView` via `NSViewRepresentable` |
| `ThoxWarRoom iOS`   | iOS 17+   | iPhone       | SwiftUI | `WKWebView` via `UIViewRepresentable` |

Both targets share the same Swift sources in `App/` — platform-conditional via `#if os(macOS)` / `#if os(iOS)`. The bundle identifier is `ai.thox.warroom` for both. Apple Developer Team: `DVJ6Z5343U` (THOX AI LLC).

## Project layout

```
thoxwarroom/
├── project.yml                 # XcodeGen — single source of truth for the Xcode project
├── App/
│   ├── ThoxWarRoomApp.swift    # @main App, scene wiring, dark appearance
│   ├── ContentView.swift       # Root view: WKWebView + branded overlay
│   ├── WebViewRepresentable.swift  # macOS NSViewRepresentable + iOS UIViewRepresentable
│   ├── ThoxWebViewModel.swift  # ObservableObject: load state, navigation policy
│   ├── ThoxTheme.swift         # THOX emerald accent + dark surfaces
│   ├── LoadingOverlay.swift    # Branded spinner + offline/Retry
│   └── ThoxWarRoom.entitlements # App sandbox + network client
├── Assets.xcassets/            # Xcode asset catalog (icons + accent color)
│   ├── AppIcon.appiconset/     # iOS universal icons
│   └── AppIcon-mac.appiconset/ # macOS icons
├── Resources/                  # Standalone AppIcon.icns (for productbuild/DMG fallback)
│   ├── AppIcon-master.png      # 1024x1024 master
│   ├── AppIcon.icns
│   └── AppIcon.appiconset/     # Loose iOS iconset (mirrored into Assets.xcassets)
├── Tests/
│   └── ThoxWarRoomTests.swift  # Navigation policy + load state machine tests
├── scripts/
│   ├── gen_appiconset.py       # Regenerate THOX-green chip-mark icons
│   ├── build_macos.sh          # Developer ID signed, notarized, stapled macOS DMG
│   ├── build_ios.sh            # Archive + TestFlight upload
│   ├── ci.sh                   # Local CI (no GitHub Actions)
│   └── smoke_test.sh           # E2E launch + persistent login check
├── .env.example                # APPLE_ID / APPLE_PASSWORD placeholders
├── AGENTS.md                   # Project conventions for AI workers
└── README.md
```

## Build & run

```bash
# 1) Generate the Xcode project from project.yml
xcodegen generate

# 2) Build + test
./scripts/ci.sh

# 3) Build a release-ready Developer ID + notarized macOS DMG.
# NOTARY_PROFILE must already exist in the login Keychain.
NOTARY_PROFILE=THOX_NOTARY ./scripts/build_macos.sh
# Output: build/macos/ThoxWarRoom-Release-arm64.dmg

# Credential-free local packaging check (explicitly not release-ready)
SIGNING_MODE=unsigned SKIP_NOTARIZE=1 ./scripts/build_macos.sh

# 4) Build the iOS app + upload to TestFlight
APPLE_ID=you@apple.com APPLE_PASSWORD=app-specific-pw \
    ./scripts/build_ios.sh
# Output: build/ios/export/ThoxWarRoom.ipa
```

### Launch the macOS app

```bash
open build/macos/derived/Build/Products/Release/ThoxWarRoom.app
```

The window loads `https://webui.thox.ai` and persists the session cookie via `WKWebsiteDataStore.default()` so the next launch stays signed in.

## Behavior

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

12 unit tests cover:

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

## CI

`scripts/ci.sh` runs locally (no remote runners):

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

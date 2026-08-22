# ThoxWarRoom

Native SwiftUI wrapper for [webui.thox.ai](https://webui.thox.ai).

## Build

```bash
xcodegen generate
./scripts/ci.sh           # local CI: regenerate, build, test
./scripts/build_macos.sh  # signed .app + arm64 .dmg
./scripts/build_ios.sh    # archive + TestFlight upload
```

## Conventions

- Swift 5.10, SwiftUI, single codebase for macOS 14+ + iOS 17+
- `WKWebView` wrapped in `NSViewRepresentable` (macOS) + `UIViewRepresentable` (iOS) — NOT the iOS 26 SwiftUI `WebView` (same libswiftWebKit pitfall as MeshStack)
- Persistent session via `WKWebsiteDataStore.default()`
- Off-domain navigation → system browser (cancel the in-app nav)
- Dark-mode-first: `preferredColorScheme(.dark)` + macOS `NSApp.appearance = .darkAqua`
- Branded overlay (spinner + error/retry) over the WKWebView — never a white screen
- Apple Team `DVJ6Z5343U` (THOX AI LLC), bundle id `ai.thox.warroom`
- App Sandbox + Hardened Runtime enabled on macOS
- Code signing: Automatic

## Layout

- `App/` — Swift sources (single tree, `#if os(...)` for platform differences)
- `Assets.xcassets/` — Xcode asset catalog (icons, accent color)
- `Tests/` — XCTest unit tests for `ThoxWebViewModel`
- `scripts/` — `gen_appiconset.py`, `build_macos.sh`, `build_ios.sh`, `ci.sh`, `smoke_test.sh`
- `Resources/` — standalone `AppIcon.icns` for productbuild/DMG fallback

## Tests

```bash
xcodebuild -project ThoxWarRoom.xcodeproj -scheme "ThoxWarRoom macOS" \
    -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO test
```

8 tests cover the navigation policy and load state machine. No live WKWebView in unit tests.

## Lessons learned (carry over from MeshStack)

- Don't use the iOS 26 SwiftUI `WebView`; it's iOS 26+ only and the libswiftWebKit linkage is fragile across Xcode minor versions.
- Don't trust `xcpretty` availability — pipe to `tee log >/dev/null` and tail the log instead.
- Watch out for `NSApp.appearance = ...` inside `App.init()` — `NSApp.shared` is nil until after init. Defer via `applicationDidFinishLaunching` notification.
- `osascript` requires Accessibility permission on macOS 26 (Tahoe); `cua-driver` works without it.
- Screen Recording permission is needed for `screencapture`; cua-driver's AX capture is the more reliable smoke-test signal.

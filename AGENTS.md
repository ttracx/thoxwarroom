# Project

ThoxWarRoom is a native Flutter client for iOS and Android, forked from Conduit (GPL-3.0), customized for THOX.ai LLC. It connects to self-hosted Open WebUI servers, direct model endpoints (including ThoxRoute), and Hermes Agent instances — with an integrated War Room dashboard for THOX fleet, MeshStack/MeshCore, and ThoxRoute monitoring.

# Build, codegen, and verification

```bash
flutter pub get
dart run build_runner build
flutter run -d ios
# or
flutter run -d android
```

```bash
flutter pub get
dart run build_runner build
flutter test
```

Run `dart run build_runner build` after `flutter pub get` and after switching branches. Generated `*.g.dart` and `*.freezed.dart` files are git-ignored but required by analyzer/test runs.

# Architecture & layout

Top-level Dart code is split into `lib/core/` for app-wide services, models, routing, auth, storage, networking, and platform glue; `lib/features/` for product areas; `lib/shared/` for reusable widgets and utilities; and `lib/l10n/` for localization.

The `lib/features/warroom/` module is THOX-specific, providing fleet/mesh/ThoxRoute monitoring via a dedicated dashboard tab.

State management uses Riverpod 3 with generated providers. Navigation uses `go_router`. HTTP and realtime transport use Dio and `socket_io_client`. Local persistence uses Drift for structured data, `shared_preferences` for preferences, and `flutter_secure_storage` for credentials.

# Conventions

Use `DebugLogger` from `lib/core/utils/debug_logger.dart` for diagnostics, with slash-scoped `scope:` values. Tests use `package:checks`, `flutter_test`, and `mocktail`. Lints come from `flutter_lints` and `riverpod_lint`.

# Design System

ThoxWarRoom uses the ThoxOS design system (emerald accent, dark-first). See `lib/shared/theme/tweakcn_themes.dart` for the `thoxos` theme variant. All new UI must follow the ThoxOS design tokens.

# THOX Technology Integration

- **ThoxRoute**: route.thox.ai/v1 — 12 workspace model categories
- **MeshStack/MeshCore**: COBS+CBOR+CRC32C protocol at 921600 baud
- **Fleet**: KnightHub WSL2 (primary), Windows (funnel), MacBook (secondary), HF Sentinel (failover)
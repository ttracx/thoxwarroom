# Contributing to ThoxWarRoom

## Design System Compliance

ThoxWarRoom follows the ThoxOS design system. All UI contributions must adhere to:

- **Dark-first**: True black (#000000) backgrounds in dark mode, gray-900 (#0B0B0C) surfaces
- **Emerald accent only**: #10B981 (emerald-500) for primary actions, focus, selection
- **Radius**: Controls 12px, containers 16px
- **Borders**: Hairline (border-white/10 dark, border-gray-200 light)
- **Typography**: Geist Sans for body, Geist Mono for metrics/data
- **No external CDN references**: Fonts are bundled, no external icon hosts

## Development Setup

```bash
git clone --recursive https://github.com/ttracx/thoxwarroom.git
cd thoxwarroom
flutter pub get
dart run build_runner build
```

## Code Style

- Use `DebugLogger` for diagnostics with slash-scoped `scope:` values
- Tests use `package:checks`, `flutter_test`, and `mocktail`
- Lints from `flutter_lints` and `riverpod_lint`
- State management: Riverpod 3 with generated providers
- Navigation: `go_router`

## Pull Request Process

1. Open an issue or discussion before starting work on major changes
2. Branch from `main`
3. Run `dart run build_runner build` after `flutter pub get`
4. Ensure `flutter test` and `flutter analyze` pass
5. Sign off commits with `Signed-off-by: Your Name <email>`

## License

By contributing, you agree that your contributions will be licensed under the GPL-3.0 License.

Copyright (c) 2024-2026 THOX.ai LLC. All rights reserved.
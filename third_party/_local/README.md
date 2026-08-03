# third_party/_local — local katex/katex_dart fork

These paths shadow the submodule packages in `../katex/packages/` because the
upstream `orestesgaolin/katex` submodule is read-only from this repo, and the
upstream code as of `fdb0a3dc2ccf` (katex_dart 0.1.1) has two build-blocking
issues on the current Flutter stable (3.44.8 / Dart 3.12.2):

1. `packages/katex_dart/pubspec.yaml` pins `meta: ^1.18.3`, but
   flutter_test from the Flutter SDK pins `meta 1.18.0`, so version solving
   fails. Local copy relaxes to `>=1.18.0 <2.0.0`.
2. `packages/katex/lib/katex.dart` only exports the wrapper, not the
   `katex_dart` box-tree types (`SvgPathNode`, `SvgPreserveAspectRatio`,
   `BoxNode`, ...). `mermaid_core` references those via `as kx` so they must
   be re-exported. Local copy adds
   `export 'package:katex_dart/katex_dart.dart';`.

If upstream adopts these fixes, drop `third_party/_local/` and point the
dependency_overrides back at the submodule paths.

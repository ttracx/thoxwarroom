/// A Flutter widget that renders LaTeX math by painting the box tree produced
/// by the pure-Dart `katex` package.
///
/// See `PLAN.md` and `tickets/BOARD.md` at the repo root for status.
library;

export 'src/animated_math_widget.dart';
export 'src/font_mapping.dart';
export 'src/math_span.dart' show mathSpan;
export 'src/math_widget.dart';
export 'src/render/box_painter.dart';
// Re-export the pure-Dart box tree so consumers importing `package:katex`
// (e.g. mermaid_core's math path) can reference BoxNode types directly.
export 'package:katex_dart/katex_dart.dart';

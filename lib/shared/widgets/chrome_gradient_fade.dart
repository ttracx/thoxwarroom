import 'package:flutter/widgets.dart';

import '../theme/theme_extensions.dart';

const double kThoxWarRoomChromeFadeHeight = 30.0;

enum ThoxWarRoomChromeFadeEdge { top, bottom }

/// Gradient-only chrome edge used when custom Flutter bars replace native bars.
///
/// This intentionally does not blur. It gives transparent custom chrome the
/// same soft scroll-edge separation as the adaptive bars while keeping the
/// underlying content readable.
class ThoxWarRoomChromeGradientFade extends StatelessWidget {
  const ThoxWarRoomChromeGradientFade({
    super.key,
    required this.edge,
    required this.contentHeight,
    this.fadeHeight = kThoxWarRoomChromeFadeHeight,
  });

  const ThoxWarRoomChromeGradientFade.top({
    super.key,
    required this.contentHeight,
    this.fadeHeight = kThoxWarRoomChromeFadeHeight,
  }) : edge = ThoxWarRoomChromeFadeEdge.top;

  const ThoxWarRoomChromeGradientFade.bottom({
    super.key,
    required this.contentHeight,
    this.fadeHeight = kThoxWarRoomChromeFadeHeight,
  }) : edge = ThoxWarRoomChromeFadeEdge.bottom;

  final ThoxWarRoomChromeFadeEdge edge;
  final double contentHeight;
  final double fadeHeight;

  @override
  Widget build(BuildContext context) {
    final baseColor = context.thoxTheme.surfaceBackground;
    final height = contentHeight + fadeHeight;
    final colors = edge == ThoxWarRoomChromeFadeEdge.top
        ? [
            baseColor.withValues(alpha: 0.92),
            baseColor.withValues(alpha: 0.72),
            baseColor.withValues(alpha: 0.28),
            baseColor.withValues(alpha: 0.0),
          ]
        : [
            baseColor.withValues(alpha: 0.0),
            baseColor.withValues(alpha: 0.28),
            baseColor.withValues(alpha: 0.72),
            baseColor.withValues(alpha: 0.92),
          ];

    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
              stops: const [0.0, 0.3, 0.65, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:math';
import 'package:flutter/material.dart';
import '../models/insights_models.dart';

/// CustomPainter-based bar chart for daily usage.
class UsageBarChart extends StatelessWidget {
  final List<DailyUsage> data;

  const UsageBarChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      color: isDark ? const Color(0xFF0B0B0C) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE4E4E7),
        ),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily Activity',
              style: TextStyle(
                fontFamily: 'Geist Sans',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: CustomPaint(
                size: Size.infinite,
                painter: _BarChartPainter(
                  data: data,
                  isDark: isDark,
                  accent: const Color(0xFF10B981),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<DailyUsage> data;
  final bool isDark;
  final Color accent;

  _BarChartPainter({
    required this.data,
    required this.isDark,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final maxVal = data.fold(0, (max, d) => d.totalPrompts > max ? d.totalPrompts : max);
    if (maxVal == 0) return;

    final barWidth = size.width / data.length;
    final chartHeight = size.height - 30; // Leave room for labels
    final labelColor = isDark ? Colors.white38 : Colors.black38;

    for (var i = 0; i < data.length; i++) {
      final barHeight = (data[i].totalPrompts / maxVal) * chartHeight;
      final x = i * barWidth + barWidth * 0.15;
      final y = chartHeight - barHeight;
      final w = barWidth * 0.7;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, barHeight),
        const Radius.circular(4),
      );

      final paint = Paint()
        ..color = accent.withValues(alpha: 0.8)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(rect, paint);

      // Draw label every few bars to avoid crowding
      if (data.length <= 7 || i % (data.length ~/ 7 + 1) == 0) {
        final labelPainter = TextPainter(
          text: TextSpan(
            text: '${data[i].date.day}/${data[i].date.month}',
            style: TextStyle(
              fontFamily: 'Geist Sans',
              fontSize: 9,
              color: labelColor,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        labelPainter.layout();
        labelPainter.paint(
          canvas,
          Offset(x + w / 2 - labelPainter.width / 2, chartHeight + 8),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter old) =>
      old.data != data || old.isDark != isDark;
}

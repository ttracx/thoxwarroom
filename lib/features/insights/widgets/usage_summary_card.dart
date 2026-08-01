import 'package:flutter/material.dart';
import '../models/insights_models.dart';

/// Summary card showing total prompts, tokens, and avg latency.
class UsageSummaryCard extends StatelessWidget {
  final UsageSummary summary;

  const UsageSummaryCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = const Color(0xFF10B981);

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
            Row(
              children: [
                Icon(Icons.analytics_outlined, color: accent, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Usage Summary',
                  style: TextStyle(
                    fontFamily: 'Geist Sans',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: 'Prompts',
                    value: '${summary.totalPrompts}',
                    color: accent,
                  ),
                ),
                Expanded(
                  child: _StatTile(
                    label: 'Tokens',
                    value: _formatTokens(summary.totalTokens),
                    color: const Color(0xFF3B82F6),
                  ),
                ),
                Expanded(
                  child: _StatTile(
                    label: 'Avg/day',
                    value: summary.avgDailyPrompts.toStringAsFixed(1),
                    color: const Color(0xFFA855F7),
                  ),
                ),
              ],
            ),
            if (summary.mostUsedModel != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.model_training, size: 14, color: isDark ? Colors.white38 : Colors.black38),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Most used: ${summary.mostUsedModel}',
                      style: TextStyle(
                        fontFamily: 'Geist Sans',
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTokens(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '$count';
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatTile({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Geist Sans',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Geist Sans',
            fontSize: 11,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white38
                : Colors.black38,
          ),
        ),
      ],
    );
  }
}

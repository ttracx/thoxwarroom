import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/insights_models.dart';
import '../providers/insights_providers.dart';
import '../widgets/usage_summary_card.dart';
import '../widgets/usage_bar_chart.dart';

/// Usage Insights dashboard page.
class InsightsPage extends ConsumerWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = const Color(0xFF10B981);
    final summary = ref.watch(usageSummaryProvider);
    final dateFilter = ref.watch(dateRangeFilterProvider);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.analytics_outlined, color: accent, size: 20),
            const SizedBox(width: 8),
            Text(
              'Insights',
              style: TextStyle(
                fontFamily: 'Geist Sans',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
        backgroundColor: isDark ? Colors.black : const Color(0xFFFAFAFA),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          PopupMenuButton<DateRangeFilter>(
            icon: Icon(Icons.calendar_month, color: accent),
            onSelected: (filter) {
              ref.read(dateRangeFilterProvider.notifier).state = filter;
            },
            itemBuilder: (context) => DateRangeFilter.values
                .map((f) => PopupMenuItem(
                      value: f,
                      child: Row(
                        children: [
                          if (dateFilter == f)
                            Icon(Icons.check, color: accent, size: 16),
                          if (dateFilter == f) const SizedBox(width: 8),
                          Text(f.label),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
      body: ListView(
        children: [
          UsageSummaryCard(summary: summary),
          if (summary.dailyBreakdown.isNotEmpty)
            UsageBarChart(data: summary.dailyBreakdown),
          const SizedBox(height: 8),
          _MostUsedModelsCard(summary: summary, isDark: isDark, accent: accent),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _MostUsedModelsCard extends StatelessWidget {
  final UsageSummary summary;
  final bool isDark;
  final Color accent;

  const _MostUsedModelsCard({
    required this.summary,
    required this.isDark,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
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
                Icon(Icons.trending_up, color: accent, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Model Usage',
                  style: TextStyle(
                    fontFamily: 'Geist Sans',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (summary.mostUsedModel == null)
              Text(
                'No usage data yet.',
                style: TextStyle(
                  fontFamily: 'Geist Sans',
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              )
            else ...[
              // Show models from daily breakdown
              ...summary.dailyBreakdown
                  .expand((d) => d.modelsUsed)
                  .toSet()
                  .map((model) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(Icons.circle, size: 8, color: accent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                model,
                                style: TextStyle(
                                  fontFamily: 'Geist Sans',
                                  fontSize: 13,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (model == summary.mostUsedModel)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'TOP',
                                  style: TextStyle(
                                    fontFamily: 'Geist Sans',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: accent,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ))
                  ,
            ],
          ],
        ),
      ),
    );
  }
}

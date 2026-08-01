import 'package:flutter/material.dart';

/// Individual usage stat entry.
@immutable
class UsageStat {
  const UsageStat({
    required this.date,
    required this.promptCount,
    required this.tokenCount,
    required this.modelUsed,
    required this.durationMs,
  });

  final DateTime date;
  final int promptCount;
  final int tokenCount;
  final String modelUsed;
  final int durationMs;
}

/// Aggregated daily usage.
@immutable
class DailyUsage {
  const DailyUsage({
    required this.date,
    required this.totalPrompts,
    required this.totalTokens,
    required this.avgLatencyMs,
    required this.modelsUsed,
  });

  final DateTime date;
  final int totalPrompts;
  final int totalTokens;
  final double avgLatencyMs;
  final List<String> modelsUsed;
}

/// Overall usage summary.
@immutable
class UsageSummary {
  const UsageSummary({
    required this.totalPrompts,
    required this.totalTokens,
    required this.avgDailyPrompts,
    required this.mostUsedModel,
    required this.dailyBreakdown,
  });

  final int totalPrompts;
  final int totalTokens;
  final double avgDailyPrompts;
  final String? mostUsedModel;
  final List<DailyUsage> dailyBreakdown;
}

enum DateRangeFilter { week, month, allTime }

extension DateRangeFilterX on DateRangeFilter {
  String get label {
    switch (this) {
      case DateRangeFilter.week:
        return '7 days';
      case DateRangeFilter.month:
        return '30 days';
      case DateRangeFilter.allTime:
        return 'All time';
    }
  }

  int get days {
    switch (this) {
      case DateRangeFilter.week:
        return 7;
      case DateRangeFilter.month:
        return 30;
      case DateRangeFilter.allTime:
        return 0; // unlimited
    }
  }
}

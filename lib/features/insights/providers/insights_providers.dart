import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/debug_logger.dart';
import '../models/insights_models.dart';

const _usageKey = 'thoxwarroom.usage_stats';

/// Provider for SharedPreferences.
final _prefsProvider = FutureProvider<SharedPreferences>((ref) async {
  return SharedPreferences.getInstance();
});

/// Raw usage stats provider — loads from local persistence.
final usageStatsProvider =
    StateNotifierProvider<UsageStatsNotifier, List<UsageStat>>(
  (ref) => UsageStatsNotifier(ref),
);

class UsageStatsNotifier extends StateNotifier<List<UsageStat>> {
  UsageStatsNotifier(this._ref) : super([]) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    try {
      final prefs = await _ref.read(_prefsProvider.future);
      final raw = prefs.getString(_usageKey);
      if (raw != null) {
        final list = (jsonDecode(raw) as List)
            .map((e) => UsageStat(
                  date: DateTime.parse(e['date']),
                  promptCount: e['prompt_count'] as int,
                  tokenCount: e['token_count'] as int,
                  modelUsed: e['model_used'] as String,
                  durationMs: e['duration_ms'] as int,
                ))
            .toList();
        state = list;
      }
    } catch (e) {
      DebugLogger.log('Failed to load usage stats: $e', scope: 'insights/load');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await _ref.read(_prefsProvider.future);
      await prefs.setString(
        _usageKey,
        jsonEncode(state.map((e) => {
              'date': e.date.toIso8601String(),
              'prompt_count': e.promptCount,
              'token_count': e.tokenCount,
              'model_used': e.modelUsed,
              'duration_ms': e.durationMs,
            }).toList()),
      );
    } catch (e) {
      DebugLogger.log('Failed to persist usage stats: $e', scope: 'insights/persist');
    }
  }

  void recordUsage(UsageStat stat) {
    state = [...state, stat];
    _persist();
  }

  void clearStats() {
    state = [];
    _persist();
  }
}

/// Date range filter state.
final dateRangeFilterProvider = StateProvider<DateRangeFilter>(
  (ref) => DateRangeFilter.month,
);

/// Aggregated usage summary based on the selected date range.
final usageSummaryProvider = Provider<UsageSummary>((ref) {
  final stats = ref.watch(usageStatsProvider);
  final filter = ref.watch(dateRangeFilterProvider);

  var filtered = stats;
  if (filter.days > 0) {
    final cutoff = DateTime.now().subtract(Duration(days: filter.days));
    filtered = stats.where((s) => s.date.isAfter(cutoff)).toList();
  }

  if (filtered.isEmpty) {
    return UsageSummary(
      totalPrompts: 0,
      totalTokens: 0,
      avgDailyPrompts: 0,
      mostUsedModel: null,
      dailyBreakdown: [],
    );
  }

  final totalPrompts = filtered.fold(0, (sum, s) => sum + s.promptCount);
  final totalTokens = filtered.fold(0, (sum, s) => sum + s.tokenCount);

  // Group by day
  final byDay = <String, List<UsageStat>>{};
  for (final s in filtered) {
    final key = '${s.date.year}-${s.date.month}-${s.date.day}';
    byDay.putIfAbsent(key, () => []).add(s);
  }

  final dailyBreakdown = byDay.entries.map((e) {
    final dayStats = e.value;
    final dayPrompts = dayStats.fold(0, (sum, s) => sum + s.promptCount);
    final dayTokens = dayStats.fold(0, (sum, s) => sum + s.tokenCount);
    final avgLatency = dayStats.fold(0, (sum, s) => sum + s.durationMs) /
        dayStats.length;
    final models = dayStats.map((s) => s.modelUsed).toSet().toList();
    return DailyUsage(
      date: dayStats.first.date,
      totalPrompts: dayPrompts,
      totalTokens: dayTokens,
      avgLatencyMs: avgLatency.toDouble(),
      modelsUsed: models,
    );
  }).toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  // Most used model
  final modelCounts = <String, int>{};
  for (final s in filtered) {
    modelCounts[s.modelUsed] = (modelCounts[s.modelUsed] ?? 0) + s.promptCount;
  }
  final mostUsed = modelCounts.entries
      .reduce((a, b) => a.value > b.value ? a : b)
      .key;

  final daysSpan = dailyBreakdown.isNotEmpty ? dailyBreakdown.length : 1;
  final avgDaily = totalPrompts / daysSpan;

  return UsageSummary(
    totalPrompts: totalPrompts,
    totalTokens: totalTokens,
    avgDailyPrompts: avgDaily,
    mostUsedModel: mostUsed,
    dailyBreakdown: dailyBreakdown,
  );
});

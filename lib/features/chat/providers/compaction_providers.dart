import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/debug_logger.dart';
import '../models/compaction_models.dart';
import '../services/context_compaction_service.dart';

const _compactionKey = 'thoxwarroom.compaction_config';

/// Persists compaction config to SharedPreferences.
final compactionConfigProvider =
    StateNotifierProvider<CompactionConfigNotifier, CompactionConfig>(
  (ref) => CompactionConfigNotifier(),
);

class CompactionConfigNotifier extends StateNotifier<CompactionConfig> {
  CompactionConfigNotifier() : super(const CompactionConfig()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_compactionKey);
      if (raw != null) {
        state = CompactionConfig.fromJson(jsonDecode(raw));
      }
    } catch (e) {
      DebugLogger.log('Failed to load compaction config: $e', scope: 'compaction/config');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_compactionKey, jsonEncode(state.toJson()));
    } catch (e) {
      DebugLogger.log('Failed to persist compaction config: $e', scope: 'compaction/config');
    }
  }

  void update(CompactionConfig config) {
    state = config;
    _persist();
  }

  void setEnabled(bool enabled) {
    state = state.copyWith(enabled: enabled);
    _persist();
  }

  void setThreshold(int tokens) {
    state = state.copyWith(tokenThreshold: tokens);
    _persist();
  }

  void setKeepRecent(int count) {
    state = state.copyWith(keepRecentMessages: count);
    _persist();
  }
}

/// Provider for the compaction service instance.
final contextCompactionServiceProvider = Provider<ContextCompactionService>((ref) {
  return ContextCompactionService(ref.read(compactionConfigProvider));
});

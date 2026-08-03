import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/debug_logger.dart';
import '../models/spotlight_models.dart';
import '../services/spotlight_window_service.dart';

const _spotlightKey = 'thoxwarroom.spotlight_config';

/// Provider for SharedPreferences.
final _prefsProvider = FutureProvider<SharedPreferences>((ref) async {
  return SharedPreferences.getInstance();
});

/// Spotlight configuration provider, persisted to SharedPreferences.
final spotlightConfigProvider =
    StateNotifierProvider<SpotlightConfigNotifier, SpotlightConfig>(
  (ref) => SpotlightConfigNotifier(ref),
);

class SpotlightConfigNotifier extends StateNotifier<SpotlightConfig> {
  SpotlightConfigNotifier(this._ref) : super(const SpotlightConfig()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    try {
      final prefs = await _ref.read(_prefsProvider.future);
      final raw = prefs.getString(_spotlightKey);
      if (raw != null) {
        state = SpotlightConfig(
          enabled: jsonDecode(raw)['enabled'] as bool? ?? true,
          shortcut: jsonDecode(raw)['shortcut'] as String? ?? SpotlightConfig.defaultShortcut(),
          autoFocus: jsonDecode(raw)['auto_focus'] as bool? ?? true,
          sendOnEnter: jsonDecode(raw)['send_on_enter'] as bool? ?? true,
          clearAfterSend: jsonDecode(raw)['clear_after_send'] as bool? ?? true,
        );
      }
    } catch (e) {
      DebugLogger.log('Failed to load spotlight config: $e', scope: 'spotlight/config');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await _ref.read(_prefsProvider.future);
      await prefs.setString(_spotlightKey, jsonEncode({
        'enabled': state.enabled,
        'shortcut': state.shortcut,
        'auto_focus': state.autoFocus,
        'send_on_enter': state.sendOnEnter,
        'clear_after_send': state.clearAfterSend,
      }));
    } catch (e) {
      DebugLogger.log('Failed to persist spotlight config: $e', scope: 'spotlight/config');
    }
  }

  void setEnabled(bool enabled) {
    state = state.copyWith(enabled: enabled);
    _persist();
  }

  void update(SpotlightConfig config) {
    state = config;
    _persist();
  }
}

/// Whether the Spotlight window is currently visible.
final spotlightVisibleProvider = StateProvider<bool>((ref) => false);

/// Provider for the SpotlightWindowService singleton.
final spotlightServiceProvider = Provider<SpotlightWindowService>((ref) {
  return SpotlightWindowService();
});

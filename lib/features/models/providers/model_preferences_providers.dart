import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/debug_logger.dart';
import '../models/model_preferences.dart';

const _favoritesKey = 'thoxwarroom.model_favorites';
const _recentsKey = 'thoxwarroom.model_recents';
const _maxRecents = 10;

/// Provider for SharedPreferences instance.
final _prefsProvider = FutureProvider<SharedPreferences>((ref) async {
  return SharedPreferences.getInstance();
});

/// StateNotifier for model favorites, persisted to SharedPreferences.
final modelFavoritesProvider =
    StateNotifierProvider<ModelFavoritesNotifier, List<ModelFavorite>>(
  (ref) => ModelFavoritesNotifier(ref),
);

class ModelFavoritesNotifier extends StateNotifier<List<ModelFavorite>> {
  ModelFavoritesNotifier(this._ref) : super([]) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    try {
      final prefs = await _ref.read(_prefsProvider.future);
      final raw = prefs.getString(_favoritesKey);
      if (raw != null) {
        final list = (jsonDecode(raw) as List)
            .map((e) => ModelFavorite.fromJson(e as Map<String, dynamic>))
            .toList();
        state = list;
      }
    } catch (e) {
      DebugLogger.log('Failed to load favorites: $e', scope: 'models/favorites');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await _ref.read(_prefsProvider.future);
      await prefs.setString(
        _favoritesKey,
        jsonEncode(state.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      DebugLogger.log('Failed to persist favorites: $e', scope: 'models/favorites');
    }
  }

  void toggleFavorite(ModelFavorite favorite) {
    final exists = state.any((f) => f.id == favorite.id);
    if (exists) {
      state = state.where((f) => f.id != favorite.id).toList();
    } else {
      state = [...state, favorite];
    }
    _persist();
  }

  void removeFavorite(String id) {
    state = state.where((f) => f.id != id).toList();
    _persist();
  }

  bool isFavorite(String id) => state.any((f) => f.id == id);

  void reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final list = [...state];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    state = list;
    _persist();
  }
}

/// StateNotifier for recently used models, persisted to SharedPreferences.
final modelRecentsProvider =
    StateNotifierProvider<ModelRecentsNotifier, List<ModelRecent>>(
  (ref) => ModelRecentsNotifier(ref),
);

class ModelRecentsNotifier extends StateNotifier<List<ModelRecent>> {
  ModelRecentsNotifier(this._ref) : super([]) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    try {
      final prefs = await _ref.read(_prefsProvider.future);
      final raw = prefs.getString(_recentsKey);
      if (raw != null) {
        final list = (jsonDecode(raw) as List)
            .map((e) => ModelRecent.fromJson(e as Map<String, dynamic>))
            .toList();
        state = list;
      }
    } catch (e) {
      DebugLogger.log('Failed to load recents: $e', scope: 'models/recents');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await _ref.read(_prefsProvider.future);
      await prefs.setString(
        _recentsKey,
        jsonEncode(state.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      DebugLogger.log('Failed to persist recents: $e', scope: 'models/recents');
    }
  }

  void addRecent(ModelRecent recent) {
    // Remove existing entry with same id, then prepend
    state = state.where((r) => r.id != recent.id).toList();
    state = [recent, ...state].take(_maxRecents).toList();
    _persist();
  }

  void clearRecents() {
    state = [];
    _persist();
  }
}

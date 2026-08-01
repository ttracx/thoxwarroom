import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/debug_logger.dart';
import '../models/automation_models.dart';

/// Dio instance for automations API calls.
final _automationsDioProvider = Provider<Dio>((ref) {
  return Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));
});

/// Fetches automations from the Open WebUI API.
final automationsProvider =
    AsyncNotifierProvider<AutomationsNotifier, List<Automation>>(
  AutomationsNotifier.new,
);

class AutomationsNotifier extends AsyncNotifier<List<Automation>> {
  @override
  Future<List<Automation>> build() async {
    return _fetch();
  }

  Future<List<Automation>> _fetch() async {
    final dio = ref.read(_automationsDioProvider);
    try {
      DebugLogger.log('Fetching automations', scope: 'automations/fetch');
      final response = await dio.get('/api/v1/automations/');
      final List<dynamic> data = response.data as List<dynamic>;
      return data
          .map((e) => Automation.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      DebugLogger.log('Failed to fetch automations: ${e.message}', scope: 'automations/fetch');
      return [];
    }
  }

  Future<void> create(Automation automation) async {
    final dio = ref.read(_automationsDioProvider);
    try {
      final response = await dio.post(
        '/api/v1/automations/',
        data: automation.toJson(),
      );
      final created = Automation.fromJson(response.data as Map<String, dynamic>);
      state = AsyncData([...?state.value, created]);
    } on DioException catch (e) {
      DebugLogger.log('Failed to create automation: ${e.message}', scope: 'automations/create');
      rethrow;
    }
  }

  Future<void> update(Automation automation) async {
    final dio = ref.read(_automationsDioProvider);
    try {
      final response = await dio.put(
        '/api/v1/automations/${automation.id}',
        data: automation.toJson(),
      );
      final updated = Automation.fromJson(response.data as Map<String, dynamic>);
      state = AsyncData(
        ?state.value.map((a) => a.id == updated.id ? updated : a).toList(),
      );
    } on DioException catch (e) {
      DebugLogger.log('Failed to update automation: ${e.message}', scope: 'automations/update');
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    final dio = ref.read(_automationsDioProvider);
    try {
      await dio.delete('/api/v1/automations/$id');
      state = AsyncData(?state.value.where((a) => a.id != id).toList());
    } on DioException catch (e) {
      DebugLogger.log('Failed to delete automation: ${e.message}', scope: 'automations/delete');
      rethrow;
    }
  }

  Future<void> toggle(String id) async {
    final dio = ref.read(_automationsDioProvider);
    try {
      final response = await dio.post('/api/v1/automations/$id/toggle');
      final updated = Automation.fromJson(response.data as Map<String, dynamic>);
      state = AsyncData(
        ?state.value.map((a) => a.id == updated.id ? updated : a).toList(),
      );
    } on DioException catch (e) {
      DebugLogger.log('Failed to toggle automation: ${e.message}', scope: 'automations/toggle');
      rethrow;
    }
  }
}

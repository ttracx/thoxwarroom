import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/debug_logger.dart';
import '../models/memories_models.dart';

/// Provider for the Dio instance used by memories API calls.
/// In production, this would read from the existing ApiService's Dio instance.
final _memoriesDioProvider = Provider<Dio>((ref) {
  return Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));
});

/// Fetches AI memories from the Open WebUI API.
final memoriesProvider =
    AsyncNotifierProvider<MemoriesNotifier, List<AiMemory>>(
  MemoriesNotifier.new,
);

class MemoriesNotifier extends AsyncNotifier<List<AiMemory>> {
  @override
  Future<List<AiMemory>> build() async {
    return _fetchMemories();
  }

  Future<List<AiMemory>> _fetchMemories() async {
    final dio = ref.read(_memoriesDioProvider);
    try {
      DebugLogger.log('Fetching memories', scope: 'memories/fetch');
      final response = await dio.get('/api/v1/memories/');
      final List<dynamic> data = response.data as List<dynamic>;
      return data
          .map((e) => AiMemory.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      DebugLogger.log('Failed to fetch memories: ${e.message}',
          scope: 'memories/fetch');
      return [];
    }
  }

  Future<void> createMemory(String content, {MemoryCategory? category}) async {
    final dio = ref.read(_memoriesDioProvider);
    try {
      DebugLogger.log('Creating memory', scope: 'memories/create');
      final response = await dio.post(
        '/api/v1/memories/',
        data: {
          'content': content,
          if (category != null) 'category': category.name,
        },
      );
      final memory = AiMemory.fromJson(response.data as Map<String, dynamic>);
      state = AsyncData([...?state.value, memory]);
    } on DioException catch (e) {
      DebugLogger.log('Failed to create memory: ${e.message}',
          scope: 'memories/create');
      rethrow;
    }
  }

  Future<void> updateMemory(AiMemory memory) async {
    final dio = ref.read(_memoriesDioProvider);
    try {
      DebugLogger.log('Updating memory ${memory.id}',
          scope: 'memories/update');
      final response = await dio.put(
        '/api/v1/memories/${memory.id}',
        data: memory.toJson(),
      );
      final updated =
          AiMemory.fromJson(response.data as Map<String, dynamic>);
      state = AsyncData(
        state.value?.map((m) => m.id == updated.id ? updated : m).toList() ??
            <AiMemory>[],
      );
    } on DioException catch (e) {
      DebugLogger.log('Failed to update memory: ${e.message}',
          scope: 'memories/update');
      rethrow;
    }
  }

  Future<void> deleteMemory(String id) async {
    final dio = ref.read(_memoriesDioProvider);
    try {
      DebugLogger.log('Deleting memory $id', scope: 'memories/delete');
      await dio.delete('/api/v1/memories/$id');
      state = AsyncData(
        state.value?.where((m) => m.id != id).toList() ?? <AiMemory>[],
      );
    } on DioException catch (e) {
      DebugLogger.log('Failed to delete memory: ${e.message}',
          scope: 'memories/delete');
      rethrow;
    }
  }
}
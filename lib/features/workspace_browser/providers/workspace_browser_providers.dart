import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/debug_logger.dart';
import '../models/workspace_file_models.dart';
import '../services/workspace_browser_service.dart';

/// Dio instance for workspace browser API calls.
final _wbDioProvider = Provider<Dio>((ref) {
  return Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));
});

/// Provider for the WorkspaceBrowserService.
final workspaceBrowserServiceProvider = Provider<WorkspaceBrowserService>((ref) {
  return WorkspaceBrowserService(ref.read(_wbDioProvider));
});

/// Current directory path.
final workspaceCurrentPathProvider = StateProvider<String>((ref) => '/');

/// Directory listing for the current path.
final workspaceEntriesProvider = FutureProvider.autoDispose<List<WorkspaceEntry>>((ref) async {
  final path = ref.watch(workspaceCurrentPathProvider);
  final service = ref.read(workspaceBrowserServiceProvider);
  try {
    return service.listDirectory(path);
  } catch (e) {
    DebugLogger.log('Failed to list $path: $e', scope: 'workspace_browser/entries');
    return [];
  }
});

/// File content provider (family — takes a file path).
final workspaceFileContentProvider =
    FutureProvider.autoDispose.family<WorkspaceFileContent, String>((ref, path) async {
  final service = ref.read(workspaceBrowserServiceProvider);
  return service.readFile(path);
});

/// Search provider.
final workspaceSearchQueryProvider = StateProvider<String>((ref) => '');
final workspaceSearchProvider =
    FutureProvider.autoDispose<List<WorkspaceSearchResult>>((ref) async {
  final query = ref.watch(workspaceSearchQueryProvider);
  if (query.isEmpty) return [];
  final service = ref.read(workspaceBrowserServiceProvider);
  try {
    return service.searchFiles(query);
  } catch (e) {
    DebugLogger.log('Search failed: $e', scope: 'workspace_browser/search');
    return [];
  }
});

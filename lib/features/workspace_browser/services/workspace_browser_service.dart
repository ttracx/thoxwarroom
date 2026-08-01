import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/utils/debug_logger.dart';
import '../models/workspace_file_models.dart';

/// Dio-based service for browsing the Hermes workspace file system.
class WorkspaceBrowserService {
  WorkspaceBrowserService(this._dio);

  final Dio _dio;

  /// List directory contents.
  Future<List<WorkspaceEntry>> listDirectory(String path) async {
    try {
      final response = await _dio.get(
        '/api/v1/files/list',
        queryParameters: {'path': path},
      );
      final List<dynamic> entries = response.data ?? [];
      return entries.map((e) {
        final map = e as Map<String, dynamic>;
        return WorkspaceEntry(
          path: map['path']?.toString() ?? '',
          name: map['name']?.toString() ?? '',
          isDirectory: map['is_directory'] as bool? ?? false,
          size: map['size'] as int? ?? 0,
          modifiedAt: DateTime.tryParse(map['modified_at']?.toString() ?? '') ??
              DateTime.now(),
          permissions: map['permissions']?.toString() ?? '',
          type: map['is_symlink'] == true
              ? WorkspaceEntryType.symlink
              : (map['is_directory'] == true
                  ? WorkspaceEntryType.directory
                  : WorkspaceEntryType.file),
        );
      }).toList();
    } on DioException catch (e) {
      DebugLogger.log('Failed to list directory: ${e.message}', scope: 'workspace_browser/list');
      rethrow;
    }
  }

  /// Read file content.
  Future<WorkspaceFileContent> readFile(String path) async {
    try {
      final response = await _dio.get(
        '/api/v1/files/read',
        queryParameters: {'path': path},
      );
      final data = response.data as Map<String, dynamic>;
      return WorkspaceFileContent(
        path: path,
        content: data['content']?.toString() ?? '',
        language: data['language']?.toString() ?? 'text',
        isBinary: data['is_binary'] as bool? ?? false,
        size: data['size'] as int? ?? 0,
      );
    } on DioException catch (e) {
      DebugLogger.log('Failed to read file: ${e.message}', scope: 'workspace_browser/read');
      rethrow;
    }
  }

  /// Search files by content.
  Future<List<WorkspaceSearchResult>> searchFiles(String query) async {
    try {
      final response = await _dio.get(
        '/api/v1/files/search',
        queryParameters: {'q': query},
      );
      final List<dynamic> results = response.data ?? [];
      return results.map((r) {
        final map = r as Map<String, dynamic>;
        return WorkspaceSearchResult(
          path: map['path']?.toString() ?? '',
          line: map['line'] as int? ?? 0,
          lineContent: map['line_content']?.toString() ?? '',
          matchCount: map['match_count'] as int? ?? 0,
        );
      }).toList();
    } on DioException catch (e) {
      DebugLogger.log('Failed to search: ${e.message}', scope: 'workspace_browser/search');
      rethrow;
    }
  }

  /// Upload a file.
  Future<void> uploadFile(String path, Uint8List data) async {
    try {
      final formData = FormData.fromMap({
        'path': path,
        'file': MultipartFile.fromBytes(data),
      });
      await _dio.post('/api/v1/files/upload', data: formData);
    } on DioException catch (e) {
      DebugLogger.log('Failed to upload: ${e.message}', scope: 'workspace_browser/upload');
      rethrow;
    }
  }

  /// Create a directory.
  Future<void> createDirectory(String path) async {
    try {
      await _dio.post('/api/v1/files/mkdir', data: {'path': path});
    } on DioException catch (e) {
      DebugLogger.log('Failed to create directory: ${e.message}', scope: 'workspace_browser/mkdir');
      rethrow;
    }
  }

  /// Delete a file or directory.
  Future<void> deleteEntry(String path) async {
    try {
      await _dio.delete('/api/v1/files/delete', queryParameters: {'path': path});
    } on DioException catch (e) {
      DebugLogger.log('Failed to delete: ${e.message}', scope: 'workspace_browser/delete');
      rethrow;
    }
  }

  /// Rename a file or directory.
  Future<void> renameEntry(String oldPath, String newPath) async {
    try {
      await _dio.post('/api/v1/files/rename', data: {
        'old_path': oldPath,
        'new_path': newPath,
      });
    } on DioException catch (e) {
      DebugLogger.log('Failed to rename: ${e.message}', scope: 'workspace_browser/rename');
      rethrow;
    }
  }
}

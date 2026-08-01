import 'package:flutter/material.dart';

/// Type of a workspace entry.
enum WorkspaceEntryType { file, directory, symlink }

extension WorkspaceEntryTypeX on WorkspaceEntryType {
  IconData get icon {
    switch (this) {
      case WorkspaceEntryType.file:
        return Icons.insert_drive_file_outlined;
      case WorkspaceEntryType.directory:
        return Icons.folder_outlined;
      case WorkspaceEntryType.symlink:
        return Icons.link_outlined;
    }
  }
}

/// A file or directory entry in the workspace.
@immutable
class WorkspaceEntry {
  const WorkspaceEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.modifiedAt,
    this.permissions = '',
    this.type = WorkspaceEntryType.file,
    this.children,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime modifiedAt;
  final String permissions;
  final WorkspaceEntryType type;
  final List<WorkspaceEntry>? children;

  String get fileExtension {
    if (isDirectory) return '';
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot + 1) : '';
  }

  IconData get icon {
    if (isDirectory) return Icons.folder_outlined;
    switch (fileExtension) {
      case 'dart':
        return Icons.code;
      case 'py':
        return Icons.code;
      case 'js':
      case 'ts':
        return Icons.javascript;
      case 'json':
        return Icons.data_object;
      case 'md':
        return Icons.description_outlined;
      case 'yaml':
      case 'yml':
        return Icons.settings_outlined;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'svg':
        return Icons.image_outlined;
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }
}

/// Content of a workspace file.
@immutable
class WorkspaceFileContent {
  const WorkspaceFileContent({
    required this.path,
    required this.content,
    required this.language,
    required this.isBinary,
    required this.size,
  });

  final String path;
  final String content;
  final String language;
  final bool isBinary;
  final int size;
}

/// A search result from the workspace.
@immutable
class WorkspaceSearchResult {
  const WorkspaceSearchResult({
    required this.path,
    required this.line,
    required this.lineContent,
    required this.matchCount,
  });

  final String path;
  final int line;
  final String lineContent;
  final int matchCount;
}

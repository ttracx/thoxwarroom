import 'package:flutter/material.dart';
import '../models/workspace_file_models.dart';

/// List tile for a workspace file or directory entry.
class WorkspaceFileTile extends StatelessWidget {
  final WorkspaceEntry entry;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const WorkspaceFileTile({
    super.key,
    required this.entry,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = const Color(0xFF10B981);

    return ListTile(
      leading: Icon(
        entry.icon,
        size: 22,
        color: entry.isDirectory ? accent : (isDark ? Colors.white60 : Colors.black54),
      ),
      title: Text(
        entry.name,
        style: TextStyle(
          fontFamily: 'Geist Sans',
          fontSize: 14,
          fontWeight: entry.isDirectory ? FontWeight.w500 : FontWeight.w400,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      subtitle: entry.isDirectory
          ? null
          : Text(
              _formatSize(entry.size),
              style: TextStyle(
                fontFamily: 'Geist Sans',
                fontSize: 11,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
      trailing: entry.isDirectory
          ? Icon(Icons.chevron_right, size: 20, color: isDark ? Colors.white30 : Colors.black26)
          : null,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

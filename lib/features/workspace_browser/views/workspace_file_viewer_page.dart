import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';

import '../providers/workspace_browser_providers.dart';

/// Simple file content viewer with syntax highlighting.
class WorkspaceFileViewerPage extends ConsumerWidget {
  final String path;

  const WorkspaceFileViewerPage({super.key, required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = const Color(0xFF10B981);
    final content = ref.watch(workspaceFileContentProvider(path));

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Text(
          path.split('/').last,
          style: TextStyle(
            fontFamily: 'Geist Sans',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        backgroundColor: isDark ? Colors.black : const Color(0xFFFAFAFA),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
      ),
      body: content.when(
        data: (file) {
          if (file.isBinary) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image_outlined, size: 48, color: accent.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text(
                    'Binary file — preview not available',
                    style: TextStyle(
                      fontFamily: 'Geist Sans',
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${file.size} bytes',
                    style: TextStyle(
                      fontFamily: 'Geist Sans',
                      fontSize: 12,
                      color: isDark ? Colors.white30 : Colors.black26,
                    ),
                  ),
                ],
              ),
            );
          }
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: HighlightView(
                file.content,
                language: file.language,
                theme: atomOneDarkTheme,
                padding: const EdgeInsets.all(12),
                textStyle: const TextStyle(
                  fontFamily: 'Geist Mono',
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Failed to load file',
            style: TextStyle(fontFamily: 'Geist Sans', color: isDark ? Colors.white38 : Colors.black38),
          ),
        ),
      ),
    );
  }
}

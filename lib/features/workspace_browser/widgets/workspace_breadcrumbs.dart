import 'package:flutter/material.dart';

/// Breadcrumb navigation for the workspace file browser.
class WorkspaceBreadcrumbs extends StatelessWidget {
  final String currentPath;
  final ValueChanged<String> onNavigate;

  const WorkspaceBreadcrumbs({
    super.key,
    required this.currentPath,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = const Color(0xFF10B981);

    final segments = currentPath.split('/').where((s) => s.isNotEmpty).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Root
          GestureDetector(
            onTap: () => onNavigate('/'),
            child: Icon(Icons.home_outlined, size: 18, color: accent),
          ),
          for (var i = 0; i < segments.length; i++) ...[
            Icon(Icons.chevron_right, size: 16, color: isDark ? Colors.white24 : Colors.black24),
            GestureDetector(
              onTap: () {
                final path = '/${segments.sublist(0, i + 1).join('/')}';
                onNavigate(path);
              },
              child: Text(
                segments[i],
                style: TextStyle(
                  fontFamily: 'Geist Sans',
                  fontSize: 13,
                  color: i == segments.length - 1
                      ? (isDark ? Colors.white : Colors.black)
                      : accent,
                  fontWeight: i == segments.length - 1 ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

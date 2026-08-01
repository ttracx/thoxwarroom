import 'package:flutter/material.dart';

/// Compact response view for the Spotlight, showing streaming markdown.
class SpotlightResponseView extends StatelessWidget {
  final String response;
  final bool isStreaming;

  const SpotlightResponseView({
    super.key,
    required this.response,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = const Color(0xFF10B981);

    if (response.isEmpty && !isStreaming) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.smart_toy_outlined, size: 14, color: accent),
              const SizedBox(width: 6),
              Text(
                'Response',
                style: TextStyle(
                  fontFamily: 'Geist Sans',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
              if (isStreaming) ...[
                const SizedBox(width: 6),
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: accent),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: Text(
                response,
                style: TextStyle(
                  fontFamily: 'Geist Sans',
                  fontSize: 13,
                  height: 1.4,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

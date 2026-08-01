import 'package:flutter/material.dart';
import '../models/memories_models.dart';

/// Card widget for displaying a single AI memory.
class MemoryCard extends StatelessWidget {
  final AiMemory memory;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDismissed;

  const MemoryCard({
    super.key,
    required this.memory,
    this.onTap,
    this.onLongPress,
    this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = memory.category?.badgeColor ?? const Color(0xFF10B981);

    return Card(
      color: isDark ? const Color(0xFF0B0B0C) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE4E4E7),
        ),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (memory.category != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(memory.category!.icon, size: 12, color: accent),
                          const SizedBox(width: 4),
                          Text(
                            memory.category!.label,
                            style: TextStyle(
                              fontFamily: 'Geist Sans',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(
                memory.content,
                style: TextStyle(
                  fontFamily: 'Geist Sans',
                  fontSize: 14,
                  height: 1.4,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                'Updated ${_formatTime(memory.updatedAt)}',
                style: TextStyle(
                  fontFamily: 'Geist Sans',
                  fontSize: 11,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}
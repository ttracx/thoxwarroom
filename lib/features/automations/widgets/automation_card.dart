import 'package:flutter/material.dart';
import '../models/automation_models.dart';

/// Card showing an automation with status, schedule, and toggle.
class AutomationCard extends StatelessWidget {
  final Automation automation;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onToggle;

  const AutomationCard({
    super.key,
    required this.automation,
    this.onTap,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = const Color(0xFF10B981);

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
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      automation.title,
                      style: TextStyle(
                        fontFamily: 'Geist Sans',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: automation.status.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      automation.status.label,
                      style: TextStyle(
                        fontFamily: 'Geist Sans',
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: automation.status.color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                automation.prompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Geist Sans',
                  fontSize: 13,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.schedule, size: 14, color: accent),
                  const SizedBox(width: 4),
                  Text(
                    automation.scheduleType.label,
                    style: TextStyle(
                      fontFamily: 'Geist Sans',
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                  const Spacer(),
                  if (automation.nextRunAt != null) ...[
                    Icon(Icons.next_plan, size: 14, color: isDark ? Colors.white38 : Colors.black38),
                    const SizedBox(width: 4),
                    Text(
                      'Next: ${_formatTime(automation.nextRunAt!)}',
                      style: TextStyle(
                        fontFamily: 'Geist Sans',
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ],
              ),
              if (onToggle != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Switch.adaptive(
                      value: automation.status == AutomationStatus.active,
                      onChanged: onToggle,
                      activeColor: accent,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

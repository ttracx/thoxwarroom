import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/automation_models.dart';

/// Bottom sheet form for creating/editing automations.
class AutomationEditorSheet extends ConsumerStatefulWidget {
  final Automation? existing;

  const AutomationEditorSheet({super.key, this.existing});

  @override
  ConsumerState<AutomationEditorSheet> createState() => _AutomationEditorSheetState();
}

class _AutomationEditorSheetState extends ConsumerState<AutomationEditorSheet> {
  late TextEditingController _titleController;
  late TextEditingController _promptController;
  late TextEditingController _cronController;
  String _modelId = '';
  AutomationSchedule _scheduleType = AutomationSchedule.daily;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existing?.title ?? '');
    _promptController = TextEditingController(text: widget.existing?.prompt ?? '');
    _cronController = TextEditingController(text: widget.existing?.schedule ?? '0 9 * * *');
    _modelId = widget.existing?.modelId ?? '';
    _scheduleType = widget.existing?.scheduleType ?? AutomationSchedule.daily;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _promptController.dispose();
    _cronController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = const Color(0xFF10B981);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0B0B0C) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.existing == null ? 'New Automation' : 'Edit Automation',
                style: TextStyle(
                  fontFamily: 'Geist Sans',
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 20),
              _field(_titleController, 'Title'),
              const SizedBox(height: 12),
              _field(_promptController, 'Prompt', maxLines: 4),
              const SizedBox(height: 16),
              Text('Schedule', style: _labelStyle(isDark)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: AutomationSchedule.values.map((s) {
                  final selected = _scheduleType == s;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _scheduleType = s;
                      if (s != AutomationSchedule.custom) {
                        _cronController.text = s.defaultCron;
                      }
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? accent.withValues(alpha: 0.15) : (isDark ? Colors.black : const Color(0xFFF4F4F5)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: selected ? accent : Colors.transparent, width: 1.5),
                      ),
                      child: Text(
                        s.label,
                        style: TextStyle(
                          fontFamily: 'Geist Sans',
                          fontSize: 12,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected ? accent : (isDark ? Colors.white60 : Colors.black54),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (_scheduleType == AutomationSchedule.custom) ...[
                const SizedBox(height: 12),
                _field(_cronController, 'Cron expression'),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Save', style: TextStyle(fontFamily: 'Geist Sans', fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, {int maxLines = 1}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(fontFamily: 'Geist Sans', color: isDark ? Colors.white : Colors.black),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontFamily: 'Geist Sans', color: isDark ? Colors.white38 : Colors.black38),
        filled: true,
        fillColor: isDark ? Colors.black : const Color(0xFFF4F4F5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: const Color(0xFF10B981), width: 2)),
      ),
    );
  }

  TextStyle _labelStyle(bool isDark) => TextStyle(
        fontFamily: 'Geist Sans',
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: isDark ? Colors.white60 : Colors.black54,
      );

  void _save() {
    if (_titleController.text.trim().isEmpty) return;
    Navigator.of(context).pop(
      Automation(
        id: widget.existing?.id ?? '',
        title: _titleController.text.trim(),
        prompt: _promptController.text.trim(),
        modelId: _modelId,
        schedule: _cronController.text.trim(),
        scheduleType: _scheduleType,
        status: widget.existing?.status ?? AutomationStatus.active,
        lastRunAt: widget.existing?.lastRunAt,
        nextRunAt: widget.existing?.nextRunAt,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
        chatId: widget.existing?.chatId,
      ),
    );
  }
}

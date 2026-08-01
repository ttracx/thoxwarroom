import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/memories_models.dart';

/// Bottom sheet for creating or editing an AI memory.
class MemoryEditorSheet extends ConsumerStatefulWidget {
  final AiMemory? existing;

  const MemoryEditorSheet({super.key, this.existing});

  @override
  ConsumerState<MemoryEditorSheet> createState() => _MemoryEditorSheetState();
}

class _MemoryEditorSheetState extends ConsumerState<MemoryEditorSheet> {
  late TextEditingController _contentController;
  MemoryCategory _category = MemoryCategory.fact;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.existing?.content ?? '');
    _category = widget.existing?.category ?? MemoryCategory.fact;
  }

  @override
  void dispose() {
    _contentController.dispose();
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existing == null ? 'New Memory' : 'Edit Memory',
              style: TextStyle(
                fontFamily: 'Geist Sans',
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _contentController,
              maxLines: 4,
              autofocus: true,
              style: TextStyle(
                fontFamily: 'Geist Sans',
                color: isDark ? Colors.white : Colors.black,
              ),
              decoration: InputDecoration(
                labelText: 'Memory content',
                labelStyle: TextStyle(
                  fontFamily: 'Geist Sans',
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                filled: true,
                fillColor: isDark ? Colors.black : const Color(0xFFF4F4F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark
                        ? const Color(0x1AFFFFFF)
                        : const Color(0xFFE4E4E7),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: accent, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Category',
              style: TextStyle(
                fontFamily: 'Geist Sans',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: MemoryCategory.values.map((cat) {
                final selected = _category == cat;
                return GestureDetector(
                  onTap: () => setState(() => _category = cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? cat.badgeColor.withValues(alpha: 0.15)
                          : (isDark ? Colors.black : const Color(0xFFF4F4F5)),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? cat.badgeColor : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(cat.icon, size: 14, color: cat.badgeColor),
                        const SizedBox(width: 6),
                        Text(
                          cat.label,
                          style: TextStyle(
                            fontFamily: 'Geist Sans',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: selected
                                ? cat.badgeColor
                                : (isDark ? Colors.white70 : Colors.black54),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Save',
                  style: TextStyle(
                    fontFamily: 'Geist Sans',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _save() {
    final content = _contentController.text.trim();
    if (content.isEmpty) return;
    Navigator.of(context).pop(
      AiMemory(
        id: widget.existing?.id ?? '',
        content: content,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
        category: _category,
      ),
    );
  }
}
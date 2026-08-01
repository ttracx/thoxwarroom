import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/composer_shortcut_models.dart';
import '../providers/composer_shortcut_providers.dart';

/// Overlay widget that appears above the text input when a trigger char is detected.
class ShortcutPickerOverlay extends ConsumerStatefulWidget {
  final ShortcutDetection detection;
  final ValueChanged<ComposerShortcutItem> onSelected;
  final VoidCallback onDismiss;

  const ShortcutPickerOverlay({
    super.key,
    required this.detection,
    required this.onSelected,
    required this.onDismiss,
  });

  @override
  ConsumerState<ShortcutPickerOverlay> createState() => _ShortcutPickerOverlayState();
}

class _ShortcutPickerOverlayState extends ConsumerState<ShortcutPickerOverlay> {
  int _selectedIndex = 0;
  List<ComposerShortcutItem> _items = [];
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  void _loadItems() {
    switch (widget.detection.trigger) {
      case ComposerShortcutTrigger.at:
        ref.read(shortcutModelListProvider.future).then((items) {
          _setItems(items);
        });
        break;
      case ComposerShortcutTrigger.slash:
        ref.read(shortcutPromptListProvider.future).then((items) {
          _setItems(items);
        });
        break;
      case ComposerShortcutTrigger.dollar:
        ref.read(shortcutSkillListProvider.future).then((items) {
          _setItems(items);
        });
        break;
      case ComposerShortcutTrigger.hash:
        ref.read(shortcutKnowledgeListProvider.future).then((items) {
          _setItems(items);
        });
        break;
    }
  }

  void _setItems(List<ComposerShortcutItem> items) {
    final filtered = items.where((item) {
      if (widget.detection.searchTerm.isEmpty) return true;
      return item.label.toLowerCase().contains(widget.detection.searchTerm.toLowerCase());
    }).toList();
    setState(() {
      _items = filtered;
      _selectedIndex = 0;
    });
  }

  @override
  bool handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _selectedIndex = (_selectedIndex + 1) % _items.length;
        });
        _scrollToSelected();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _selectedIndex = (_selectedIndex - 1) % _items.length;
        });
        _scrollToSelected();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_items.isNotEmpty && _selectedIndex < _items.length) {
          widget.onSelected(_items[_selectedIndex]);
        }
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        widget.onDismiss();
        return true;
      }
    }
    return false;
  }

  void _scrollToSelected() {
    if (_scrollController.hasClients) {
      final offset = _selectedIndex * 48.0;
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = const Color(0xFF10B981);

    return Focus(
      onKeyEvent: handleKeyEvent,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 280, maxWidth: 500),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0B0B0C) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE4E4E7),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              ),
              child: Row(
                children: [
                  Icon(widget.detection.trigger.icon, size: 14, color: accent),
                  const SizedBox(width: 6),
                  Text(
                    widget.detection.trigger.label,
                    style: TextStyle(
                      fontFamily: 'Geist Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
            // Items list
            Flexible(
              child: ListView.builder(
                controller: _scrollController,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final selected = index == _selectedIndex;
                  return InkWell(
                    onTap: () => widget.onSelected(item),
                    child: Container(
                      color: selected
                          ? accent.withValues(alpha: 0.12)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          if (item.icon != null)
                            Icon(item.icon, size: 16, color: selected ? accent : (isDark ? Colors.white54 : Colors.black54)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.label,
                                  style: TextStyle(
                                    fontFamily: 'Geist Sans',
                                    fontSize: 14,
                                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                                    color: selected
                                        ? accent
                                        : (isDark ? Colors.white : Colors.black87),
                                  ),
                                ),
                                if (item.subtitle != null)
                                  Text(
                                    item.subtitle!,
                                    style: TextStyle(
                                      fontFamily: 'Geist Sans',
                                      fontSize: 11,
                                      color: isDark ? Colors.white38 : Colors.black38,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No matches found',
                  style: TextStyle(
                    fontFamily: 'Geist Sans',
                    fontSize: 13,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

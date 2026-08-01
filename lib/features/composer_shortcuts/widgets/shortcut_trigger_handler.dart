import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/composer_shortcut_models.dart';
import '../providers/composer_shortcut_providers.dart';
import 'shortcut_picker_overlay.dart';

/// Widget that wraps the text input and monitors for trigger characters.
/// Manages the shortcut picker overlay state.
class ShortcutTriggerHandler extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Widget child;
  final ValueChanged<ComposerShortcutResult> onShortcutSelected;

  const ShortcutTriggerHandler({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.child,
    required this.onShortcutSelected,
  });

  @override
  State<ShortcutTriggerHandler> createState() => _ShortcutTriggerHandlerState();
}

class _ShortcutTriggerHandlerState extends State<ShortcutTriggerHandler> {
  OverlayEntry? _overlayEntry;
  ShortcutDetection? _detection;
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _removeOverlay();
    super.dispose();
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    final offset = widget.controller.selection.extentOffset;
    final detection = detectShortcut(text, offset);

    if (detection != null) {
      if (_detection?.trigger != detection.trigger ||
          _detection?.searchTerm != detection.searchTerm) {
        _removeOverlay();
        _detection = detection;
        _showOverlay();
      }
    } else {
      _removeOverlay();
      _detection = null;
    }
  }

  void _showOverlay() {
    if (_detection == null) return;
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 60,
        left: 16,
        right: 16,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, -8),
          child: ShortcutPickerOverlay(
            detection: _detection!,
            onSelected: _onItemSelected,
            onDismiss: _removeOverlay,
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onItemSelected(ComposerShortcutItem item) {
    // Replace the trigger text with the selected item reference
    final text = widget.controller.text;
    final offset = widget.controller.selection.extentOffset;
    final before = text.substring(0, offset);
    final after = text.substring(offset);

    // Find and replace the trigger + search term
    final match = RegExp(r'(?:^|\s)([@/$#])\S*$').firstMatch(before);
    if (match != null) {
      final replacement = ' ${item.trigger.triggerChar}${item.label} ';
      final newBefore = before.substring(0, match.start) + replacement;
      final newText = newBefore + after;
      widget.controller.text = newText;
      widget.controller.selection = TextSelection.collapsed(
        offset: newBefore.length,
      );
    }

    _removeOverlay();
    _detection = null;

    widget.onShortcutSelected(ComposerShortcutResult(
      trigger: item.trigger,
      selectedId: item.id,
      selectedLabel: item.label,
      insertText: '${item.trigger.triggerChar}${item.label}',
      type: _triggerToType(item.trigger),
    ));
  }

  ComposerShortcutType _triggerToType(ComposerShortcutTrigger trigger) {
    switch (trigger) {
      case ComposerShortcutTrigger.at:
        return ComposerShortcutType.model;
      case ComposerShortcutTrigger.slash:
        return ComposerShortcutType.prompt;
      case ComposerShortcutTrigger.dollar:
        return ComposerShortcutType.skill;
      case ComposerShortcutTrigger.hash:
        return ComposerShortcutType.knowledge;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: widget.child,
    );
  }
}

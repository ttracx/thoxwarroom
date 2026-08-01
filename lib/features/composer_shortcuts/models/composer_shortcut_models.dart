import 'package:flutter/material.dart';

/// Trigger character for composer shortcuts.
enum ComposerShortcutTrigger {
  at,      // @ — model picker
  slash,   // / — prompt picker
  dollar,  // $ — skill picker
  hash,    // # — knowledge base picker
}

extension ComposerShortcutTriggerX on ComposerShortcutTrigger {
  String get triggerChar {
    switch (this) {
      case ComposerShortcutTrigger.at:
        return '@';
      case ComposerShortcutTrigger.slash:
        return '/';
      case ComposerShortcutTrigger.dollar:
        return r'$';
      case ComposerShortcutTrigger.hash:
        return '#';
    }
  }

  String get label {
    switch (this) {
      case ComposerShortcutTrigger.at:
        return 'Models';
      case ComposerShortcutTrigger.slash:
        return 'Prompts';
      case ComposerShortcutTrigger.dollar:
        return 'Skills';
      case ComposerShortcutTrigger.hash:
        return 'Knowledge';
    }
  }

  IconData get icon {
    switch (this) {
      case ComposerShortcutTrigger.at:
        return Icons.smart_toy_outlined;
      case ComposerShortcutTrigger.slash:
        return Icons.description_outlined;
      case ComposerShortcutTrigger.dollar:
        return Icons.auto_awesome_outlined;
      case ComposerShortcutTrigger.hash:
        return Icons.menu_book_outlined;
    }
  }
}

/// Result type when a shortcut item is selected.
enum ComposerShortcutType { model, prompt, skill, knowledge }

/// Result returned when a user picks an item from the shortcut overlay.
@immutable
class ComposerShortcutResult {
  const ComposerShortcutResult({
    required this.trigger,
    required this.selectedId,
    required this.selectedLabel,
    required this.insertText,
    required this.type,
  });

  final ComposerShortcutTrigger trigger;
  final String selectedId;
  final String selectedLabel;
  final String insertText;
  final ComposerShortcutType type;
}

/// A single item shown in the shortcut picker overlay.
@immutable
class ComposerShortcutItem {
  const ComposerShortcutItem({
    required this.id,
    required this.label,
    required this.trigger,
    this.subtitle,
    this.icon,
  });

  final String id;
  final String label;
  final ComposerShortcutTrigger trigger;
  final String? subtitle;
  final IconData? icon;
}

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/debug_logger.dart';
import '../models/composer_shortcut_models.dart';

/// Dio instance for shortcut API calls.
final _shortcutDioProvider = Provider<Dio>((ref) {
  return Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));
});

/// Detects trigger characters in the current text at the cursor position.
/// Returns the trigger type and the search text after the trigger char,
/// or null if no trigger is active.
final composerShortcutDetectorProvider = Provider<
    ComposerShortcutResult? Function(String text, int cursorOffset)>((ref) {
  return (String text, int cursorOffset) {
    if (cursorOffset <= 0 || cursorOffset > text.length) return null;

    // Look backwards from cursor to find a trigger char at the start of a word
    final before = text.substring(0, cursorOffset);
    final triggerMatch = RegExp(r'(?:^|\s)([@/$#])(\S*)$').firstMatch(before);
    if (triggerMatch == null) return null;

    final char = triggerMatch.group(1)!;
    final trigger = ComposerShortcutTrigger.values.firstWhere(
      (t) => t.triggerChar == char,
      orElse: () => ComposerShortcutTrigger.at,
    );

    // Return null — this is used to signal the overlay to show
    return null;
  };
});

/// Detects if a trigger is active and returns the trigger + search term.
ShortcutDetection? detectShortcut(String text, int cursorOffset) {
  if (cursorOffset <= 0 || cursorOffset > text.length) return null;
  final before = text.substring(0, cursorOffset);
  final match = RegExp(r'(?:^|\s)([@/$#])(\S*)$').firstMatch(before);
  if (match == null) return null;

  final char = match.group(1)!;
  final searchTerm = match.group(2)!;
  final trigger = ComposerShortcutTrigger.values.firstWhere(
    (t) => t.triggerChar == char,
    orElse: () => ComposerShortcutTrigger.at,
  );

  return ShortcutDetection(trigger: trigger, searchTerm: searchTerm);
}

class ShortcutDetection {
  final ComposerShortcutTrigger trigger;
  final String searchTerm;
  const ShortcutDetection({required this.trigger, required this.searchTerm});
}

/// Model list for the @ picker.
final shortcutModelListProvider = FutureProvider<List<ComposerShortcutItem>>((ref) async {
  final dio = ref.read(_shortcutDioProvider);
  try {
    final response = await dio.get('/api/models');
    final List<dynamic> models = response.data?.data ?? response.data ?? [];
    return models.map((m) {
      final map = m as Map<String, dynamic>;
      return ComposerShortcutItem(
        id: map['id']?.toString() ?? '',
        label: map['name']?.toString() ?? map['id']?.toString() ?? '',
        trigger: ComposerShortcutTrigger.at,
        subtitle: map['owned_by']?.toString(),
        icon: Icons.smart_toy_outlined,
      );
    }).toList();
  } catch (e) {
    DebugLogger.log('Failed to load models for shortcut: $e', scope: 'shortcut/models');
    return [];
  }
});

/// Prompt list for the / picker.
final shortcutPromptListProvider = FutureProvider<List<ComposerShortcutItem>>((ref) async {
  final dio = ref.read(_shortcutDioProvider);
  try {
    final response = await dio.get('/api/v1/prompts/');
    final List<dynamic> prompts = response.data ?? [];
    return prompts.map((p) {
      final map = p as Map<String, dynamic>;
      return ComposerShortcutItem(
        id: map['id']?.toString() ?? '',
        label: map['title']?.toString() ?? '',
        trigger: ComposerShortcutTrigger.slash,
        subtitle: map['command']?.toString(),
        icon: Icons.description_outlined,
      );
    }).toList();
  } catch (e) {
    DebugLogger.log('Failed to load prompts: $e', scope: 'shortcut/prompts');
    return [];
  }
});

/// Skill list for the $ picker.
final shortcutSkillListProvider = FutureProvider<List<ComposerShortcutItem>>((ref) async {
  final dio = ref.read(_shortcutDioProvider);
  try {
    final response = await dio.get('/api/v1/skills/');
    final List<dynamic> skills = response.data ?? [];
    return skills.map((s) {
      final map = s as Map<String, dynamic>;
      return ComposerShortcutItem(
        id: map['id']?.toString() ?? '',
        label: map['name']?.toString() ?? '',
        trigger: ComposerShortcutTrigger.dollar,
        icon: Icons.auto_awesome_outlined,
      );
    }).toList();
  } catch (e) {
    DebugLogger.log('Failed to load skills: $e', scope: 'shortcut/skills');
    return [];
  }
});

/// Knowledge base list for the # picker.
final shortcutKnowledgeListProvider = FutureProvider<List<ComposerShortcutItem>>((ref) async {
  final dio = ref.read(_shortcutDioProvider);
  try {
    final response = await dio.get('/api/v1/knowledge/');
    final List<dynamic> knowledge = response.data ?? [];
    return knowledge.map((k) {
      final map = k as Map<String, dynamic>;
      return ComposerShortcutItem(
        id: map['id']?.toString() ?? '',
        label: map['name']?.toString() ?? '',
        trigger: ComposerShortcutTrigger.hash,
        icon: Icons.menu_book_outlined,
      );
    }).toList();
  } catch (e) {
    DebugLogger.log('Failed to load knowledge: $e', scope: 'shortcut/knowledge');
    return [];
  }
});

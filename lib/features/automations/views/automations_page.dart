import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/automation_models.dart';
import '../providers/automations_providers.dart';
import '../widgets/automation_card.dart';
import '../widgets/automation_editor_sheet.dart';

/// Page listing all automations with status badges and toggle.
class AutomationsPage extends ConsumerStatefulWidget {
  const AutomationsPage({super.key});

  @override
  ConsumerState<AutomationsPage> createState() => _AutomationsPageState();
}

class _AutomationsPageState extends ConsumerState<AutomationsPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = const Color(0xFF10B981);
    final automations = ref.watch(automationsProvider);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.schedule_outlined, color: accent, size: 20),
            const SizedBox(width: 8),
            Text(
              'Automations',
              style: TextStyle(
                fontFamily: 'Geist Sans',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
        backgroundColor: isDark ? Colors.black : const Color(0xFFFAFAFA),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditor(context),
        backgroundColor: accent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: automations.when(
        data: (list) {
          if (list.isEmpty) return _empty(isDark, accent);
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final a = list[index];
              return AutomationCard(
                automation: a,
                onTap: () => _showEditor(context, existing: a),
                onToggle: (val) {
                  ref.read(automationsProvider.notifier).toggle(a.id);
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _empty(isDark, accent),
      ),
    );
  }

  Widget _empty(bool isDark, Color accent) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_outlined, size: 64, color: accent.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            'No automations yet',
            style: TextStyle(
              fontFamily: 'Geist Sans',
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white60 : Colors.black45,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Schedule prompts to run automatically.\nTap + to create one.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Geist Sans',
              fontSize: 14,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  void _showEditor(BuildContext context, {Automation? existing}) async {
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AutomationEditorSheet(existing: existing),
    );
    if (result == null || result is! Automation) return;
    if (existing != null) {
      ref.read(automationsProvider.notifier).updateAutomation(result);
    } else {
      ref.read(automationsProvider.notifier).create(result);
    }
  }
}

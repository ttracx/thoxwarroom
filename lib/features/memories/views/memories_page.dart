import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/memories_models.dart';
import '../providers/memories_providers.dart';
import '../widgets/memory_card.dart';
import '../widgets/memory_editor_sheet.dart';

/// Page displaying AI memories with CRUD operations.
class MemoriesPage extends ConsumerStatefulWidget {
  const MemoriesPage({super.key});

  @override
  ConsumerState<MemoriesPage> createState() => _MemoriesPageState();
}

class _MemoriesPageState extends ConsumerState<MemoriesPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = const Color(0xFF10B981);
    final memories = ref.watch(memoriesProvider);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.psychology_outlined, color: accent, size: 20),
            const SizedBox(width: 8),
            Text(
              'Memories',
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
      body: memories.when(
        data: (list) {
          if (list.isEmpty) {
            return _buildEmptyState(isDark, accent);
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final memory = list[index];
              return Dismissible(
                key: ValueKey(memory.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                  child: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                ),
                confirmDismiss: (direction) async {
                  return await _confirmDelete(context, memory);
                },
                onDismissed: (direction) {
                  ref.read(memoriesProvider.notifier).deleteMemory(memory.id);
                },
                child: MemoryCard(
                  memory: memory,
                  onTap: () => _showEditor(context, existing: memory),
                  onLongPress: () => _showEditor(context, existing: memory),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _buildErrorState(isDark, accent, e.toString()),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark, Color accent) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.psychology_outlined, size: 64, color: accent.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            'No memories yet',
            style: TextStyle(
              fontFamily: 'Geist Sans',
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white60 : Colors.black45,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'AI memories persist across conversations.\nTap + to add one.',
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

  Widget _buildErrorState(bool isDark, Color accent, String error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: accent.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            'Failed to load memories',
            style: TextStyle(
              fontFamily: 'Geist Sans',
              fontSize: 16,
              color: isDark ? Colors.white60 : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }

  void _showEditor(BuildContext context, {AiMemory? existing}) async {
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MemoryEditorSheet(existing: existing),
    );
    if (result == null) return;
    if (result is AiMemory) {
      if (existing != null) {
        ref.read(memoriesProvider.notifier).updateMemory(result);
      } else {
        ref.read(memoriesProvider.notifier).createMemory(
          result.content,
          category: result.category,
        );
      }
    }
  }

  Future<bool> _confirmDelete(BuildContext context, AiMemory memory) async {
    return await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Memory'),
        content: Text('Are you sure you want to delete this memory?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
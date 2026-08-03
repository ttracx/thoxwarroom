import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/model_preferences.dart';
import '../providers/model_preferences_providers.dart';

/// Bottom sheet showing favorite models with tap-to-select and reorder.
class ModelFavoritesSheet extends ConsumerWidget {
  final ValueChanged<ModelFavorite>? onSelected;

  const ModelFavoritesSheet({super.key, this.onSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = const Color(0xFF10B981);
    final favorites = ref.watch(modelFavoritesProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0B0B0C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star_rounded, color: accent, size: 22),
              const SizedBox(width: 8),
              Text(
                'Favorite Models',
                style: TextStyle(
                  fontFamily: 'Geist Sans',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (favorites.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No favorites yet.\nStar a model to add it here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Geist Sans',
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ),
            )
          else
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                itemCount: favorites.length,
                onReorder: (oldIdx, newIdx) {
                  ref.read(modelFavoritesProvider.notifier).reorder(oldIdx, newIdx);
                },
                itemBuilder: (context, index) {
                  final fav = favorites[index];
                  return ListTile(
                    key: ValueKey(fav.id),
                    leading: Icon(Icons.drag_handle, color: isDark ? Colors.white30 : Colors.black26),
                    title: Text(
                      fav.name,
                      style: TextStyle(
                        fontFamily: 'Geist Sans',
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    subtitle: Text(
                      fav.provider,
                      style: TextStyle(
                        fontFamily: 'Geist Sans',
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
                      onPressed: () {
                        ref.read(modelFavoritesProvider.notifier).removeFavorite(fav.id);
                      },
                    ),
                    onTap: () {
                      onSelected?.call(fav);
                      Navigator.of(context).pop();
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

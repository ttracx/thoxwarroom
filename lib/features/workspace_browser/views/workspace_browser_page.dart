import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/workspace_file_models.dart';
import '../providers/workspace_browser_providers.dart';
import '../widgets/workspace_breadcrumbs.dart';
import '../widgets/workspace_file_tile.dart';
import 'workspace_file_viewer_page.dart';

/// File browser page for exploring the Hermes workspace.
class WorkspaceBrowserPage extends ConsumerStatefulWidget {
  const WorkspaceBrowserPage({super.key});

  @override
  ConsumerState<WorkspaceBrowserPage> createState() => _WorkspaceBrowserPageState();
}

class _WorkspaceBrowserPageState extends ConsumerState<WorkspaceBrowserPage> {
  final _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = const Color(0xFF10B981);
    final currentPath = ref.watch(workspaceCurrentPathProvider);
    final entries = ref.watch(workspaceEntriesProvider);
    final searchQuery = ref.watch(workspaceSearchQueryProvider);
    final searchResults = ref.watch(workspaceSearchProvider);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.folder_open_outlined, color: accent, size: 20),
            const SizedBox(width: 8),
            Text(
              'Workspace',
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
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, color: accent),
            onPressed: () {
              setState(() => _isSearching = !_isSearching);
              if (!_isSearching) {
                _searchController.clear();
                ref.read(workspaceSearchQueryProvider.notifier).state = '';
              }
            },
          ),
        ],
        bottom: _isSearching
            ? PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: TextStyle(fontFamily: 'Geist Sans', color: isDark ? Colors.white : Colors.black),
                    decoration: InputDecoration(
                      hintText: 'Search files...',
                      prefixIcon: Icon(Icons.search, color: accent, size: 20),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF0B0B0C) : const Color(0xFFF4F4F5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    ),
                    onChanged: (value) {
                      ref.read(workspaceSearchQueryProvider.notifier).state = value;
                    },
                  ),
                ),
              )
            : null,
      ),
      body: _isSearching && searchQuery.isNotEmpty
          ? _buildSearchResults(searchResults, isDark, accent)
          : Column(
              children: [
                WorkspaceBreadcrumbs(
                  currentPath: currentPath,
                  onNavigate: (path) {
                    ref.read(workspaceCurrentPathProvider.notifier).state = path;
                  },
                ),
                Divider(color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE4E4E7), height: 1),
                Expanded(
                  child: entries.when(
                    data: (list) {
                      if (list.isEmpty) {
                        return Center(
                          child: Text(
                            'Empty directory',
                            style: TextStyle(
                              fontFamily: 'Geist Sans',
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                          ),
                        );
                      }
                      // Sort: directories first, then alphabetical
                      list.sort((a, b) {
                        if (a.isDirectory != b.isDirectory) {
                          return a.isDirectory ? -1 : 1;
                        }
                        return a.name.compareTo(b.name);
                      });
                      return ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final entry = list[index];
                          return WorkspaceFileTile(
                            entry: entry,
                            onTap: () {
                              if (entry.isDirectory) {
                                ref.read(workspaceCurrentPathProvider.notifier).state = entry.path;
                              } else {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => WorkspaceFileViewerPage(path: entry.path),
                                  ),
                                );
                              }
                            },
                            onLongPress: () => _showContextMenu(context, entry),
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Text(
                        'Failed to load directory',
                        style: TextStyle(fontFamily: 'Geist Sans', color: isDark ? Colors.white38 : Colors.black38),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSearchResults(AsyncValue<List<WorkspaceSearchResult>> results, bool isDark, Color accent) {
    return results.when(
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Text('No results', style: TextStyle(fontFamily: 'Geist Sans', color: isDark ? Colors.white38 : Colors.black38)),
          );
        }
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, index) {
            final result = list[index];
            return ListTile(
              leading: Icon(Icons.search, size: 18, color: accent),
              title: Text(
                result.path,
                style: TextStyle(fontFamily: 'Geist Sans', fontSize: 13, color: isDark ? Colors.white : Colors.black87),
              ),
              subtitle: Text(
                'Line ${result.line}: ${result.lineContent}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'Geist Sans', fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WorkspaceFileViewerPage(path: result.path),
                  ),
                );
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Search failed')),
    );
  }

  void _showContextMenu(BuildContext context, WorkspaceEntry entry) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () { Navigator.pop(ctx); /* TODO: rename dialog */ },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
              title: const Text('Delete', style: TextStyle(color: Color(0xFFEF4444))),
              onTap: () async {
                Navigator.pop(ctx);
                await ref.read(workspaceBrowserServiceProvider).deleteEntry(entry.path);
                ref.invalidate(workspaceEntriesProvider);
              },
            ),
          ],
        ),
      ),
    );
  }
}

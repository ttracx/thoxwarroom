import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/spotlight_providers.dart';
import '../widgets/spotlight_response_view.dart';

/// Compact floating chat bar for the Spotlight window.
class SpotlightChatBar extends ConsumerStatefulWidget {
  final ValueChanged<String>? onSend;

  const SpotlightChatBar({super.key, this.onSend});

  @override
  ConsumerState<SpotlightChatBar> createState() => _SpotlightChatBarState();
}

class _SpotlightChatBarState extends ConsumerState<SpotlightChatBar> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  String _response = '';
  bool _isStreaming = false;
  String? _selectedModel;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend?.call(text);
    setState(() {
      _isStreaming = true;
      _response = '';
    });
    // Placeholder: in production, this would connect to the streaming service
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isStreaming = false;
          _response = 'Connected to your model endpoint. Configure a backend to get responses.';
        });
      }
    });
    if (ref.read(spotlightConfigProvider).clearAfterSend) {
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = const Color(0xFF10B981);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE4E4E7)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Input row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Model selector (compact)
                PopupMenuButton<String>(
                  tooltip: 'Select model',
                  icon: Icon(Icons.smart_toy_outlined, size: 18, color: accent),
                  onSelected: (model) => setState(() => _selectedModel = model),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'auto', child: Text('Auto')),
                    const PopupMenuItem(value: 'chat', child: Text('Chat')),
                    const PopupMenuItem(value: 'reasoning', child: Text('Reasoning')),
                    const PopupMenuItem(value: 'coder', child: Text('Coder')),
                  ],
                ),
                // Text input
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: TextStyle(
                      fontFamily: 'Geist Sans',
                      fontSize: 15,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    decoration: InputDecoration.collapsed(
                      hintText: 'Ask anything...',
                      hintStyle: TextStyle(
                        fontFamily: 'Geist Sans',
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                    textInputAction: TextInputAction.send,
                  ),
                ),
                // Send button
                Container(
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 18),
                    onPressed: _send,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    padding: EdgeInsets.zero,
                  ),
                ),
                // Close button
                IconButton(
                  icon: Icon(Icons.close, size: 16, color: isDark ? Colors.white38 : Colors.black38),
                  onPressed: () => ref.read(spotlightServiceProvider).hideSpotlight(),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
          // Response area (expands when there's content)
          if (_response.isNotEmpty || _isStreaming)
            Container(
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE4E4E7),
                  ),
                ),
              ),
              child: SingleChildScrollView(
                controller: _scrollController,
                child: SpotlightResponseView(
                  response: _response,
                  isStreaming: _isStreaming,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

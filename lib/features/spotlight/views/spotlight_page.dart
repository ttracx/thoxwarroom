import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/spotlight_providers.dart';
import 'spotlight_chat_bar.dart';

/// Page rendered inside the Spotlight floating window.
class SpotlightPage extends ConsumerWidget {
  const SpotlightPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 620),
          padding: const EdgeInsets.all(8),
          child: SpotlightChatBar(
            onSend: (text) {
              // Connect to the active backend's streaming service
            },
          ),
        ),
      ),
    );
  }
}

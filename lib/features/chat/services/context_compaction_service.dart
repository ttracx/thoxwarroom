import 'dart:convert';

import '../../../core/utils/debug_logger.dart';
import '../models/compaction_models.dart';

/// Service that compacts long conversations by summarizing older messages.
///
/// When the conversation exceeds the configured token threshold, older messages
/// are summarized into a compact summary, keeping the system prompt and the
/// most recent N messages intact.
class ContextCompactionService {
  ContextCompactionService(this._config);

  final CompactionConfig _config;

  /// Approximate token count using 4 chars = 1 token heuristic.
  int estimateTokens(List<Map<String, dynamic>> messages) {
    var totalChars = 0;
    for (final msg in messages) {
      final content = msg['content']?.toString() ?? '';
      totalChars += content.length;
      // Role adds a few tokens
      totalChars += 4;
    }
    return (totalChars / 4).round();
  }

  /// Compact a list of messages if the token count exceeds the threshold.
  /// Returns a [CompactionResult] with the compacted messages and summary.
  Future<CompactionResult> compact(
    List<Map<String, dynamic>> messages, {
    String Function(String)? summarize,
  }) async {
    if (!_config.enabled) {
      return CompactionResult(
        compactedMessages: messages,
        originalCount: messages.length,
        compactedCount: messages.length,
        estimatedTokensSaved: 0,
        summary: '',
        compactedAt: DateTime.now(),
      );
    }

    final tokenCount = estimateTokens(messages);
    if (tokenCount <= _config.tokenThreshold) {
      DebugLogger.log(
        'No compaction needed: $tokenCount tokens <= ${_config.tokenThreshold}',
        scope: 'compaction/check',
      );
      return CompactionResult(
        compactedMessages: messages,
        originalCount: messages.length,
        compactedCount: messages.length,
        estimatedTokensSaved:  0,
        summary: '',
        compactedAt: DateTime.now(),
      );
    }

    DebugLogger.log(
      'Compacting conversation: $tokenCount tokens, ${messages.length} messages',
      scope: 'compaction/start',
    );

    // Split messages into: system prompt + to-summarize + recent
    final systemMessages = <Map<String, dynamic>>[];
    final toSummarize = <Map<String, dynamic>>[];
    final recent = <Map<String, dynamic>>[];

    int index = 0;
    // Keep system messages
    if (_config.keepSystemPrompt) {
      while (index < messages.length &&
          messages[index]['role'] == 'system') {
        systemMessages.add(messages[index]);
        index++;
      }
    }

    // Keep recent N messages
    final recentStart = messages.length - _config.keepRecentMessages;
    final summaryStart = index;
    final summaryEnd = recentStart > summaryStart ? recentStart : summaryStart;

    for (var i = summaryStart; i < summaryEnd && i < messages.length; i++) {
      toSummarize.add(messages[i]);
    }

    for (var i = recentStart > 0 ? recentStart : 0;
        i < messages.length;
        i++) {
      if (i >= summaryEnd) {
        recent.add(messages[i]);
      }
    }

    // Build summary
    String summary;
    if (toSummarize.isEmpty) {
      summary = '';
    } else if (summarize != null) {
      // Use the provided summarization function (e.g., call the model)
      final conversationText = toSummarize.map((m) {
        final role = m['role']?.toString() ?? 'user';
        final content = m['content']?.toString() ?? '';
        return '$role: $content';
      }).join('\n');
      summary = summarize(conversationText);
    } else {
      // Fallback: extract key points heuristically
      summary = _heuristicSummary(toSummarize);
    }

    // Build compacted message list
    final compacted = <Map<String, dynamic>>[];
    compacted.addAll(systemMessages);
    if (summary.isNotEmpty) {
      compacted.add({
        'role': 'system',
        'content': '[Conversation Summary]\n$summary',
      });
    }
    compacted.addAll(recent);

    final savedTokens = tokenCount - estimateTokens(compacted);

    DebugLogger.log(
      'Compaction complete: ${messages.length} -> ${compacted.length} messages, ~$savedTokens tokens saved',
      scope: 'compaction/done',
    );

    return CompactionResult(
      compactedMessages: compacted,
      originalCount: messages.length,
      compactedCount: compacted.length,
      estimatedTokensSaved: savedTokens,
      summary: summary,
      compactedAt: DateTime.now(),
    );
  }

  /// Heuristic summary without calling a model.
  /// Extracts the first 500 chars of each assistant message.
  String _heuristicSummary(List<Map<String, dynamic>> messages) {
    final buffer = StringBuffer();
    for (final msg in messages) {
      final role = msg['role']?.toString() ?? 'user';
      final content = msg['content']?.toString() ?? '';
      if (role == 'assistant' && content.isNotEmpty) {
        final excerpt = content.length > 200
            ? '${content.substring(0, 200)}...'
            : content;
        buffer.writeln('- $excerpt');
      }
      if (buffer.length > 2000) break; // Cap summary size
    }
    return buffer.toString();
  }
}

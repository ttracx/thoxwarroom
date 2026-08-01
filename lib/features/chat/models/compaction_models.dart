import 'package:flutter/material.dart';

/// Configuration for context compaction.
@immutable
class CompactionConfig {
  const CompactionConfig({
    this.tokenThreshold = 80000,
    this.keepRecentMessages = 10,
    this.keepSystemPrompt = true,
    this.enabled = false,
  });

  final int tokenThreshold;
  final int keepRecentMessages;
  final bool keepSystemPrompt;
  final bool enabled;

  CompactionConfig copyWith({
    int? tokenThreshold,
    int? keepRecentMessages,
    bool? keepSystemPrompt,
    bool? enabled,
  }) {
    return CompactionConfig(
      tokenThreshold: tokenThreshold ?? this.tokenThreshold,
      keepRecentMessages: keepRecentMessages ?? this.keepRecentMessages,
      keepSystemPrompt: keepSystemPrompt ?? this.keepSystemPrompt,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'token_threshold': tokenThreshold,
        'keep_recent_messages': keepRecentMessages,
        'keep_system_prompt': keepSystemPrompt,
        'enabled': enabled,
      };

  factory CompactionConfig.fromJson(Map<String, dynamic> json) => CompactionConfig(
        tokenThreshold: json['token_threshold'] as int? ?? 80000,
        keepRecentMessages: json['keep_recent_messages'] as int? ?? 10,
        keepSystemPrompt: json['keep_system_prompt'] as bool? ?? true,
        enabled: json['enabled'] as bool? ?? false,
      );
}

/// Result of a context compaction operation.
@immutable
class CompactionResult {
  const CompactionResult({
    required this.compactedMessages,
    required this.originalCount,
    required this.compactedCount,
    required this.estimatedTokensSaved,
    required this.summary,
    required this.compactedAt,
  });

  final List<Map<String, dynamic>> compactedMessages;
  final int originalCount;
  final int compactedCount;
  final int estimatedTokensSaved;
  final String summary;
  final DateTime compactedAt;

  bool get wasCompacted => originalCount != compactedCount;
}

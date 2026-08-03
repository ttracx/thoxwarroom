import 'package:flutter/material.dart';

/// AI Memory model for Open WebUI memories API.
@immutable
class AiMemory {
  const AiMemory({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.category,
  });

  final String id;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final MemoryCategory? category;

  AiMemory copyWith({
    String? id,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    MemoryCategory? category,
  }) {
    return AiMemory(
      id: id ?? this.id,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      category: category ?? this.category,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        if (category != null) 'category': category!.name,
      };

  factory AiMemory.fromJson(Map<String, dynamic> json) {
    return AiMemory(
      id: json['id']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
      category: MemoryCategory.values.firstWhere(
        (e) => e.name == json['category'],
        orElse: () => MemoryCategory.fact,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AiMemory && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

enum MemoryCategory {
  fact,
  preference,
  instruction,
  context,
}

extension MemoryCategoryX on MemoryCategory {
  String get label {
    switch (this) {
      case MemoryCategory.fact:
        return 'Fact';
      case MemoryCategory.preference:
        return 'Preference';
      case MemoryCategory.instruction:
        return 'Instruction';
      case MemoryCategory.context:
        return 'Context';
    }
  }

  Color get badgeColor {
    switch (this) {
      case MemoryCategory.fact:
        return const Color(0xFF3B82F6);
      case MemoryCategory.preference:
        return const Color(0xFF10B981);
      case MemoryCategory.instruction:
        return const Color(0xFFA855F7);
      case MemoryCategory.context:
        return const Color(0xFFF59E0B);
    }
  }

  IconData get icon {
    switch (this) {
      case MemoryCategory.fact:
        return Icons.lightbulb_outline;
      case MemoryCategory.preference:
        return Icons.favorite_outline;
      case MemoryCategory.instruction:
        return Icons.rule;
      case MemoryCategory.context:
        return Icons.help_outline;
    }
  }
}
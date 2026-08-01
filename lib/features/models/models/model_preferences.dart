import 'package:flutter/material.dart';

/// A favorited model entry.
@immutable
class ModelFavorite {
  const ModelFavorite({
    required this.id,
    required this.name,
    required this.provider,
    required this.addedAt,
  });

  final String id;
  final String name;
  final String provider;
  final DateTime addedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'provider': provider,
        'added_at': addedAt.toIso8601String(),
      };

  factory ModelFavorite.fromJson(Map<String, dynamic> json) => ModelFavorite(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        provider: json['provider']?.toString() ?? '',
        addedAt: DateTime.tryParse(json['added_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

/// A recently used model entry.
@immutable
class ModelRecent {
  const ModelRecent({
    required this.id,
    required this.name,
    required this.provider,
    required this.lastUsedAt,
  });

  final String id;
  final String name;
  final String provider;
  final DateTime lastUsedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'provider': provider,
        'last_used_at': lastUsedAt.toIso8601String(),
      };

  factory ModelRecent.fromJson(Map<String, dynamic> json) => ModelRecent(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        provider: json['provider']?.toString() ?? '',
        lastUsedAt: DateTime.tryParse(json['last_used_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

import 'package:flutter/material.dart';

/// Schedule type for automations.
enum AutomationSchedule {
  hourly,
  daily,
  weekly,
  monthly,
  custom,
}

extension AutomationScheduleX on AutomationSchedule {
  String get label {
    switch (this) {
      case AutomationSchedule.hourly:
        return 'Hourly';
      case AutomationSchedule.daily:
        return 'Daily';
      case AutomationSchedule.weekly:
        return 'Weekly';
      case AutomationSchedule.monthly:
        return 'Monthly';
      case AutomationSchedule.custom:
        return 'Custom';
    }
  }

  String get defaultCron {
    switch (this) {
      case AutomationSchedule.hourly:
        return '0 * * * *';
      case AutomationSchedule.daily:
        return '0 9 * * *';
      case AutomationSchedule.weekly:
        return '0 9 * * 1';
      case AutomationSchedule.monthly:
        return '0 9 1 * *';
      case AutomationSchedule.custom:
        return '';
    }
  }
}

/// Status of an automation.
enum AutomationStatus {
  active,
  paused,
  completed,
  failed,
}

extension AutomationStatusX on AutomationStatus {
  String get label {
    switch (this) {
      case AutomationStatus.active:
        return 'ACTIVE';
      case AutomationStatus.paused:
        return 'PAUSED';
      case AutomationStatus.completed:
        return 'DONE';
      case AutomationStatus.failed:
        return 'FAILED';
    }
  }

  Color get color {
    switch (this) {
      case AutomationStatus.active:
        return const Color(0xFF22C55E);
      case AutomationStatus.paused:
        return const Color(0xFF71717A);
      case AutomationStatus.completed:
        return const Color(0xFF3B82F6);
      case AutomationStatus.failed:
        return const Color(0xFFEF4444);
    }
  }
}

/// Automation model — a scheduled prompt that runs automatically.
@immutable
class Automation {
  const Automation({
    required this.id,
    required this.title,
    required this.prompt,
    required this.modelId,
    required this.schedule,
    required this.scheduleType,
    required this.status,
    this.lastRunAt,
    this.nextRunAt,
    required this.createdAt,
    this.chatId,
  });

  final String id;
  final String title;
  final String prompt;
  final String modelId;
  final String schedule; // cron expression
  final AutomationSchedule scheduleType;
  final AutomationStatus status;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;
  final DateTime createdAt;
  final String? chatId;

  Automation copyWith({
    String? id,
    String? title,
    String? prompt,
    String? modelId,
    String? schedule,
    AutomationSchedule? scheduleType,
    AutomationStatus? status,
    DateTime? lastRunAt,
    DateTime? nextRunAt,
    DateTime? createdAt,
    String? chatId,
  }) {
    return Automation(
      id: id ?? this.id,
      title: title ?? this.title,
      prompt: prompt ?? this.prompt,
      modelId: modelId ?? this.modelId,
      schedule: schedule ?? this.schedule,
      scheduleType: scheduleType ?? this.scheduleType,
      status: status ?? this.status,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      nextRunAt: nextRunAt ?? this.nextRunAt,
      createdAt: createdAt ?? this.createdAt,
      chatId: chatId ?? this.chatId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'prompt': prompt,
        'model_id': modelId,
        'schedule': schedule,
        'schedule_type': scheduleType.name,
        'status': status.name,
        if (lastRunAt != null) 'last_run_at': lastRunAt!.toIso8601String(),
        if (nextRunAt != null) 'next_run_at': nextRunAt!.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        if (chatId != null) 'chat_id': chatId,
      };

  factory Automation.fromJson(Map<String, dynamic> json) => Automation(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        prompt: json['prompt']?.toString() ?? '',
        modelId: json['model_id']?.toString() ?? '',
        schedule: json['schedule']?.toString() ?? '0 9 * * *',
        scheduleType: AutomationSchedule.values.firstWhere(
          (e) => e.name == json['schedule_type'],
          orElse: () => AutomationSchedule.daily,
        ),
        status: AutomationStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => AutomationStatus.active,
        ),
        lastRunAt: json['last_run_at'] != null
            ? DateTime.tryParse(json['last_run_at'].toString())
            : null,
        nextRunAt: json['next_run_at'] != null
            ? DateTime.tryParse(json['next_run_at'].toString())
            : null,
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.now(),
        chatId: json['chat_id']?.toString(),
      );
}

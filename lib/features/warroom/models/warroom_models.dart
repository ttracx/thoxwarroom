import 'package:flutter/material.dart';

/// THOX fleet device model.
@immutable
class FleetDevice {
  const FleetDevice({
    required this.id,
    required this.name,
    required this.hostname,
    required this.ipAddress,
    required this.role,
    required this.status,
    required this.uptime,
    required this.cpuUsage,
    required this.memoryUsage,
    required this.diskUsage,
    this.services = const [],
    this.lastSeen,
  });

  final String id;
  final String name;
  final String hostname;
  final String ipAddress;
  final FleetDeviceRole role;
  final FleetDeviceStatus status;
  final Duration uptime;
  final double cpuUsage; // 0.0 - 1.0
  final double memoryUsage; // 0.0 - 1.0
  final double diskUsage; // 0.0 - 1.0
  final List<FleetService> services;
  final DateTime? lastSeen;

  bool get isPrimary => role == FleetDeviceRole.primary;
  bool get isOnline => status == FleetDeviceStatus.online;
}

enum FleetDeviceRole {
  primary,
  secondary,
  funnel,
  sentinel,
  worker,
}

extension FleetDeviceRoleX on FleetDeviceRole {
  String get label {
    switch (this) {
      case FleetDeviceRole.primary:
        return 'PRIMARY';
      case FleetDeviceRole.secondary:
        return 'SECONDARY';
      case FleetDeviceRole.funnel:
        return 'FUNNEL';
      case FleetDeviceRole.sentinel:
        return 'SENTINEL';
      case FleetDeviceRole.worker:
        return 'WORKER';
    }
  }

  Color get accentColor {
    switch (this) {
      case FleetDeviceRole.primary:
        return const Color(0xFF10B981); // emerald-500
      case FleetDeviceRole.secondary:
        return const Color(0xFF3B82F6); // info blue
      case FleetDeviceRole.funnel:
        return const Color(0xFFA855F7); // agentic purple
      case FleetDeviceRole.sentinel:
        return const Color(0xFFF59E0B); // warning amber
      case FleetDeviceRole.worker:
        return const Color(0xFF6366F1); // chart indigo
    }
  }
}

enum FleetDeviceStatus {
  online,
  degraded,
  offline,
  maintenance,
}

extension FleetDeviceStatusX on FleetDeviceStatus {
  String get label {
    switch (this) {
      case FleetDeviceStatus.online:
        return 'ONLINE';
      case FleetDeviceStatus.degraded:
        return 'DEGRADED';
      case FleetDeviceStatus.offline:
        return 'OFFLINE';
      case FleetDeviceStatus.maintenance:
        return 'MAINTENANCE';
    }
  }

  Color get statusColor {
    switch (this) {
      case FleetDeviceStatus.online:
        return const Color(0xFF22C55E); // thox-success
      case FleetDeviceStatus.degraded:
        return const Color(0xFFF59E0B); // thox-warning
      case FleetDeviceStatus.offline:
        return const Color(0xFFEF4444); // thox-danger
      case FleetDeviceStatus.maintenance:
        return const Color(0xFF71717A); // gray-500
    }
  }
}

/// Service running on a fleet device.
@immutable
class FleetService {
  const FleetService({
    required this.name,
    required this.status,
    required this.port,
    this.containerId,
    this.version,
  });

  final String name;
  final FleetServiceStatus status;
  final int port;
  final String? containerId;
  final String? version;
}

enum FleetServiceStatus {
  running,
  stopped,
  restarting,
  unhealthy,
}

extension FleetServiceStatusX on FleetServiceStatus {
  String get label {
    switch (this) {
      case FleetServiceStatus.running:
        return 'RUNNING';
      case FleetServiceStatus.stopped:
        return 'STOPPED';
      case FleetServiceStatus.restarting:
        return 'RESTARTING';
      case FleetServiceStatus.unhealthy:
        return 'UNHEALTHY';
    }
  }

  Color get statusColor {
    switch (this) {
      case FleetServiceStatus.running:
        return const Color(0xFF22C55E);
      case FleetServiceStatus.stopped:
        return const Color(0xFFEF4444);
      case FleetServiceStatus.restarting:
        return const Color(0xFFF59E0B);
      case FleetServiceStatus.unhealthy:
        return const Color(0xFFEF4444);
    }
  }
}

/// MeshCore node in the THOX mesh network.
@immutable
class MeshNode {
  const MeshNode({
    required this.id,
    required this.name,
    required this.nodeType,
    required this.status,
    required this.baudRate,
    required this.protocol,
    this.lastPacketAt,
    this.packetsSent = 0,
    this.packetsReceived = 0,
    this.crcErrors = 0,
  });

  final String id;
  final String name;
  final MeshNodeType nodeType;
  final MeshNodeStatus status;
  final int baudRate;
  final String protocol; // e.g. "COBS+CBOR+CRC32C"
  final DateTime? lastPacketAt;
  final int packetsSent;
  final int packetsReceived;
  final int crcErrors;
}

enum MeshNodeType {
  hub,
  sensor,
  actuator,
  bridge,
}

enum MeshNodeStatus {
  connected,
  listening,
  error,
  disconnected,
}

extension MeshNodeStatusX on MeshNodeStatus {
  Color get statusColor {
    switch (this) {
      case MeshNodeStatus.connected:
        return const Color(0xFF10B981); // emerald
      case MeshNodeStatus.listening:
        return const Color(0xFF3B82F6); // info
      case MeshNodeStatus.error:
        return const Color(0xFFEF4444); // danger
      case MeshNodeStatus.disconnected:
        return const Color(0xFF71717A); // gray
    }
  }

  String get label {
    switch (this) {
      case MeshNodeStatus.connected:
        return 'CONNECTED';
      case MeshNodeStatus.listening:
        return 'LISTENING';
      case MeshNodeStatus.error:
        return 'ERROR';
      case MeshNodeStatus.disconnected:
        return 'DISCONNECTED';
    }
  }
}

/// ThoxRoute model routing entry.
@immutable
class ThoxRouteModel {
  const ThoxRouteModel({
    required this.id,
    required this.name,
    required this.provider,
    required this.category,
    required this.status,
    required this.contextWindow,
    this.latencyMs,
    this.description,
  });

  final String id;
  final String name;
  final String provider;
  final ThoxRouteCategory category;
  final ThoxRouteStatus status;
  final int contextWindow; // in tokens
  final int? latencyMs;
  final String? description;
}

enum ThoxRouteCategory {
  auto,
  chat,
  reasoning,
  frontier,
  coder,
  vision,
  summarize,
  private,
  company,
  search,
  agentic,
  team,
}

extension ThoxRouteCategoryX on ThoxRouteCategory {
  String get label => name.toUpperCase();

  Color get accentColor {
    switch (this) {
      case ThoxRouteCategory.auto:
        return const Color(0xFF10B981); // emerald
      case ThoxRouteCategory.chat:
        return const Color(0xFF3B82F6); // blue
      case ThoxRouteCategory.reasoning:
        return const Color(0xFFA855F7); // purple
      case ThoxRouteCategory.frontier:
        return const Color(0xFF6366F1); // indigo
      case ThoxRouteCategory.coder:
        return const Color(0xFF14B8A6); // teal
      case ThoxRouteCategory.vision:
        return const Color(0xFFEC4899); // pink
      case ThoxRouteCategory.summarize:
        return const Color(0xFFF59E0B); // amber
      case ThoxRouteCategory.private:
        return const Color(0xFFEF4444); // red
      case ThoxRouteCategory.company:
        return const Color(0xFF22C55E); // green
      case ThoxRouteCategory.search:
        return const Color(0xFF38BDF8); // sky
      case ThoxRouteCategory.agentic:
        return const Color(0xFFA855F7); // purple
      case ThoxRouteCategory.team:
        return const Color(0xFF10B981); // emerald
    }
  }
}

enum ThoxRouteStatus {
  available,
  busy,
  offline,
}

extension ThoxRouteStatusX on ThoxRouteStatus {
  Color get statusColor {
    switch (this) {
      case ThoxRouteStatus.available:
        return const Color(0xFF22C55E);
      case ThoxRouteStatus.busy:
        return const Color(0xFFF59E0B);
      case ThoxRouteStatus.offline:
        return const Color(0xFFEF4444);
    }
  }

  String get label {
    switch (this) {
      case ThoxRouteStatus.available:
        return 'AVAILABLE';
      case ThoxRouteStatus.busy:
        return 'BUSY';
      case ThoxRouteStatus.offline:
        return 'OFFLINE';
    }
  }
}

/// WarRoom aggregate status snapshot.
@immutable
class WarRoomStatus {
  const WarRoomStatus({
    required this.fleetDevices,
    required this.meshNodes,
    required this.routeModels,
    required this.activeAlerts,
    required this.timestamp,
  });

  final List<FleetDevice> fleetDevices;
  final List<MeshNode> meshNodes;
  final List<ThoxRouteModel> routeModels;
  final List<WarRoomAlert> activeAlerts;
  final DateTime timestamp;

  int get onlineDevices =>
      fleetDevices.where((d) => d.isOnline).length;
  int get totalDevices => fleetDevices.length;
  int get connectedNodes =>
      meshNodes.where((n) => n.status == MeshNodeStatus.connected).length;
  int get totalNodes => meshNodes.length;
  int get availableModels =>
      routeModels.where((m) => m.status == ThoxRouteStatus.available).length;
  int get totalModels => routeModels.length;
  int get criticalAlerts =>
      activeAlerts.where((a) => a.severity == WarRoomAlertSeverity.critical).length;
}

/// Alert item for the WarRoom dashboard.
@immutable
class WarRoomAlert {
  const WarRoomAlert({
    required this.id,
    required this.title,
    required this.severity,
    required this.source,
    required this.timestamp,
    this.description,
    this.acknowledged = false,
  });

  final String id;
  final String title;
  final WarRoomAlertSeverity severity;
  final String source;
  final DateTime timestamp;
  final String? description;
  final bool acknowledged;
}

enum WarRoomAlertSeverity {
  info,
  warning,
  critical,
}

extension WarRoomAlertSeverityX on WarRoomAlertSeverity {
  Color get color {
    switch (this) {
      case WarRoomAlertSeverity.info:
        return const Color(0xFF3B82F6);
      case WarRoomAlertSeverity.warning:
        return const Color(0xFFF59E0B);
      case WarRoomAlertSeverity.critical:
        return const Color(0xFFEF4444);
    }
  }

  String get label {
    switch (this) {
      case WarRoomAlertSeverity.info:
        return 'INFO';
      case WarRoomAlertSeverity.warning:
        return 'WARN';
      case WarRoomAlertSeverity.critical:
        return 'CRIT';
    }
  }
}
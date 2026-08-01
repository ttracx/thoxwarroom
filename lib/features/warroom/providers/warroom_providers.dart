import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/warroom_models.dart';

/// Provider for the WarRoom status stream.
final warRoomStatusProvider =
    StreamProvider<WarRoomStatus>((ref) async* {
  // Emit an initial status with mock data representing the THOX fleet.
  // In production, this would poll the ThoxRoute API, MeshStack health
  // endpoints, and the fleet monitoring service.
  yield _buildInitialStatus();

  // Refresh every 30 seconds
  final timer = Timer.periodic(
    const Duration(seconds: 30),
    (_) {},
  );
  ref.onDispose(timer.cancel);

  // For now, yield updates with slight variations
  await for (final _ in Stream.periodic(const Duration(seconds: 30))) {
    yield _buildUpdatedStatus();
  }
});

/// Fleet devices list provider.
final fleetDevicesProvider = Provider<List<FleetDevice>>((ref) {
  return _buildFleetDevices();
});

/// Mesh nodes list provider.
final meshNodesProvider = Provider<List<MeshNode>>((ref) {
  return _buildMeshNodes();
});

/// ThoxRoute models list provider.
final thoxRouteModelsProvider = Provider<List<ThoxRouteModel>>((ref) {
  return _buildThoxRouteModels();
});

/// Active alerts provider.
final warRoomAlertsProvider = Provider<List<WarRoomAlert>>((ref) {
  return _buildAlerts();
});

// ─── Mock data generators ───────────────────────────────────────

WarRoomStatus _buildInitialStatus() {
  return WarRoomStatus(
    fleetDevices: _buildFleetDevices(),
    meshNodes: _buildMeshNodes(),
    routeModels: _buildThoxRouteModels(),
    activeAlerts: _buildAlerts(),
    timestamp: DateTime.now(),
  );
}

WarRoomStatus _buildUpdatedStatus() {
  final devices = _buildFleetDevices();
  final nodes = _buildMeshNodes();
  final models = _buildThoxRouteModels();
  return WarRoomStatus(
    fleetDevices: devices,
    meshNodes: nodes,
    routeModels: models,
    activeAlerts: _buildAlerts(),
    timestamp: DateTime.now(),
  );
}

List<FleetDevice> _buildFleetDevices() {
  return [
    const FleetDevice(
      id: 'knighthub-wsl2',
      name: 'KnightHub WSL2',
      hostname: 'knighthub-wsl2',
      ipAddress: '100.97.135.46',
      role: FleetDeviceRole.primary,
      status: FleetDeviceStatus.online,
      uptime: Duration(days: 12, hours: 4),
      cpuUsage: 0.34,
      memoryUsage: 0.58,
      diskUsage: 0.71,
      services: [
        FleetService(name: 'hermes-agent', status: FleetServiceStatus.running, port: 8080, containerId: 'hermes-01', version: '2.4.0'),
        FleetService(name: 'open-webui', status: FleetServiceStatus.running, port: 3001, containerId: 'nellie-webui', version: '0.9.6'),
        FleetService(name: 'thox-meshd', status: FleetServiceStatus.running, port: 9216, version: '0.1.0'),
        FleetService(name: 'tailscale', status: FleetServiceStatus.running, port: 41641),
      ],
    ),
    const FleetDevice(
      id: 'windows-funnel',
      name: 'Windows Funnel',
      hostname: 'windows-host',
      ipAddress: '100.105.6.57',
      role: FleetDeviceRole.funnel,
      status: FleetDeviceStatus.online,
      uptime: Duration(days: 5, hours: 18),
      cpuUsage: 0.22,
      memoryUsage: 0.45,
      diskUsage: 0.63,
      services: [
        FleetService(name: 'caddy-proxy', status: FleetServiceStatus.running, port: 443),
        FleetService(name: 'tailscale', status: FleetServiceStatus.running, port: 41641),
      ],
    ),
    const FleetDevice(
      id: 'macbook-secondary',
      name: 'MacBook Secondary',
      hostname: 'macbook-pro',
      ipAddress: '100.64.44.121',
      role: FleetDeviceRole.secondary,
      status: FleetDeviceStatus.degraded,
      uptime: Duration(hours: 8),
      cpuUsage: 0.67,
      memoryUsage: 0.82,
      diskUsage: 0.54,
      services: [
        FleetService(name: 'hermes-agent', status: FleetServiceStatus.unhealthy, port: 8080),
        FleetService(name: 'obsidian-sync', status: FleetServiceStatus.running, port: 3000),
      ],
      lastSeen: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
    const FleetDevice(
      id: 'hf-sentinel',
      name: 'HF Sentinel',
      hostname: 'hf-cloud-failover',
      ipAddress: '0.0.0.0',
      role: FleetDeviceRole.sentinel,
      status: FleetDeviceStatus.online,
      uptime: Duration(days: 30),
      cpuUsage: 0.12,
      memoryUsage: 0.28,
      diskUsage: 0.35,
      services: [
        FleetService(name: 'hf-endpoint', status: FleetServiceStatus.running, port: 8000),
      ],
    ),
  ];
}

List<MeshNode> _buildMeshNodes() {
  return [
    MeshNode(
      id: 'mesh-hub-01',
      name: 'MeshHub C6',
      nodeType: MeshNodeType.hub,
      status: MeshNodeStatus.connected,
      baudRate: 921600,
      protocol: 'COBS+CBOR+CRC32C_LE',
      lastPacketAt: DateTime.now().subtract(const Duration(seconds: 2)),
      packetsSent: 15420,
      packetsReceived: 14890,
      crcErrors: 3,
    ),
    MeshNode(
      id: 'mesh-sensor-01',
      name: 'Sensor Array Alpha',
      nodeType: MeshNodeType.sensor,
      status: MeshNodeStatus.connected,
      baudRate: 921600,
      protocol: 'COBS+CBOR+CRC32C_LE',
      lastPacketAt: DateTime.now().subtract(const Duration(seconds: 1)),
      packetsSent: 8200,
      packetsReceived: 8190,
      crcErrors: 0,
    ),
    MeshNode(
      id: 'mesh-bridge-01',
      name: 'ThoxBridge WiFi',
      nodeType: MeshNodeType.bridge,
      status: MeshNodeStatus.listening,
      baudRate: 921600,
      protocol: 'COBS+CBOR+CRC32C_LE',
      lastPacketAt: DateTime.now().subtract(const Duration(seconds: 15)),
      packetsSent: 1200,
      packetsReceived: 1180,
      crcErrors: 1,
    ),
    MeshNode(
      id: 'mesh-actuator-01',
      name: 'Actuator Bank Beta',
      nodeType: MeshNodeType.actuator,
      status: MeshNodeStatus.disconnected,
      baudRate: 921600,
      protocol: 'COBS+CBOR+CRC32C_LE',
      lastPacketAt: DateTime.now().subtract(const Duration(minutes: 10)),
      packetsSent: 500,
      packetsReceived: 495,
      crcErrors: 12,
    ),
  ];
}

List<ThoxRouteModel> _buildThoxRouteModels() {
  return [
    const ThoxRouteModel(
      id: 'thoxroute-auto',
      name: 'thoxroute-auto',
      provider: 'THOXRoute',
      category: ThoxRouteCategory.auto,
      status: ThoxRouteStatus.available,
      contextWindow: 128000,
      latencyMs: 240,
      description: 'Auto-routing — picks the best model for the task.',
    ),
    const ThoxRouteModel(
      id: 'thoxroute-chat',
      name: 'thoxroute-chat',
      provider: 'THOXRoute',
      category: ThoxRouteCategory.chat,
      status: ThoxRouteStatus.available,
      contextWindow: 128000,
      latencyMs: 180,
    ),
    const ThoxRouteModel(
      id: 'thoxroute-reasoning',
      name: 'thoxroute-reasoning',
      provider: 'THOXRoute',
      category: ThoxRouteCategory.reasoning,
      status: ThoxRouteStatus.available,
      contextWindow: 200000,
      latencyMs: 1200,
      description: 'Deep reasoning model with extended thinking.',
    ),
    const ThoxRouteModel(
      id: 'thoxroute-frontier',
      name: 'thoxroute-frontier',
      provider: 'THOXRoute',
      category: ThoxRouteCategory.frontier,
      status: ThoxRouteStatus.busy,
      contextWindow: 1000000,
      latencyMs: 3500,
      description: 'Frontier-scale model for complex tasks.',
    ),
    const ThoxRouteModel(
      id: 'thoxroute-coder',
      name: 'thoxroute-coder',
      provider: 'THOXRoute',
      category: ThoxRouteCategory.coder,
      status: ThoxRouteStatus.available,
      contextWindow: 256000,
      latencyMs: 320,
      description: 'Code generation and review specialist.',
    ),
    const ThoxRouteModel(
      id: 'thoxroute-vision',
      name: 'thoxroute-vision',
      provider: 'THOXRoute',
      category: ThoxRouteCategory.vision,
      status: ThoxRouteStatus.available,
      contextWindow: 128000,
      latencyMs: 450,
      description: 'Multimodal vision model.',
    ),
    const ThoxRouteModel(
      id: 'thoxroute-summarize',
      name: 'thoxroute-summarize',
      provider: 'THOXRoute',
      category: ThoxRouteCategory.summarize,
      status: ThoxRouteStatus.available,
      contextWindow: 128000,
      latencyMs: 150,
    ),
    const ThoxRouteModel(
      id: 'thoxroute-agentic',
      name: 'thoxroute-agentic',
      provider: 'THOXRoute',
      category: ThoxRouteCategory.agentic,
      status: ThoxRouteStatus.available,
      contextWindow: 200000,
      latencyMs: 800,
      description: 'Agent-optimized model with tool-use capabilities.',
    ),
    const ThoxRouteModel(
      id: 'thoxroute-team',
      name: 'thoxroute-team',
      provider: 'THOXRoute',
      category: ThoxRouteCategory.team,
      status: ThoxRouteStatus.available,
      contextWindow: 128000,
      latencyMs: 280,
      description: 'Multi-agent team coordination model.',
    ),
    const ThoxRouteModel(
      id: 'thoxroute-search',
      name: 'thoxroute-search',
      provider: 'THOXRoute',
      category: ThoxRouteCategory.search,
      status: ThoxRouteStatus.available,
      contextWindow: 64000,
      latencyMs: 500,
    ),
    const ThoxRouteModel(
      id: 'thoxroute-private',
      name: 'thoxroute-private',
      provider: 'THOXRoute',
      category: ThoxRouteCategory.private,
      status: ThoxRouteStatus.offline,
      contextWindow: 128000,
      latencyMs: null,
      description: 'Private model endpoint — currently offline.',
    ),
    const ThoxRouteModel(
      id: 'thoxroute-company',
      name: 'thoxroute-company',
      provider: 'THOXRoute',
      category: ThoxRouteCategory.company,
      status: ThoxRouteStatus.available,
      contextWindow: 128000,
      latencyMs: 200,
      description: 'Company knowledge-tuned model.',
    ),
  ];
}

List<WarRoomAlert> _buildAlerts() {
  return [
    WarRoomAlert(
      id: 'alert-001',
      title: 'MacBook Secondary: hermes-agent unhealthy',
      severity: WarRoomAlertSeverity.warning,
      source: 'macbook-secondary',
      timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
      description: 'Hermes agent on MacBook is reporting unhealthy status. Memory usage at 82%.',
    ),
    WarRoomAlert(
      id: 'alert-002',
      title: 'Actuator Bank Beta: CRC errors rising',
      severity: WarRoomAlertSeverity.warning,
      source: 'mesh-actuator-01',
      timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
      description: '12 CRC errors detected on MeshCore UART link. Check cable integrity.',
    ),
    WarRoomAlert(
      id: 'alert-003',
      title: 'thoxroute-frontier: high latency',
      severity: WarRoomAlertSeverity.info,
      source: 'thoxroute',
      timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
      description: 'Frontier model experiencing 3.5s latency. Queue depth increasing.',
    ),
    WarRoomAlert(
      id: 'alert-004',
      title: 'thoxroute-private: endpoint offline',
      severity: WarRoomAlertSeverity.critical,
      source: 'thoxroute',
      timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      description: 'Private model endpoint is offline. Failover to HF Sentinel active.',
    ),
  ];
}
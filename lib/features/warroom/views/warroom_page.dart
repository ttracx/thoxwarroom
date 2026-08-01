import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/theme/tweakcn_themes.dart';
import '../models/warroom_models.dart';
import '../providers/warroom_providers.dart';

/// WarRoom Dashboard — THOX fleet command center.
///
/// Shows real-time status of:
/// - Fleet devices (KnightHub WSL2, Windows Funnel, MacBook, HF Sentinel)
/// - MeshCore/MeshStack nodes
/// - ThoxRoute model routing
/// - Active alerts
class WarRoomPage extends ConsumerStatefulWidget {
  const WarRoomPage({super.key});

  @override
  ConsumerState<WarRoomPage> createState() => _WarRoomPageState();
}

class _WarRoomPageState extends ConsumerState<WarRoomPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final variant = theme.extension<AppPaletteThemeExtension>()?.palette ??
        TweakcnThemes.thoxos;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark
        ? const Color(0xFF0B0B0C) // gray-900
        : const Color(0xFFF4F4F5); // gray-100
    final borderColor = isDark
        ? const Color(0x1AFFFFFF) // border-white/10
        : const Color(0xFFE4E4E7);
    final accentColor = variant.dark.primary; // emerald-500

    final devices = ref.watch(fleetDevicesProvider);
    final nodes = ref.watch(meshNodesProvider);
    final models = ref.watch(thoxRouteModelsProvider);
    final alerts = ref.watch(warRoomAlertsProvider);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.dashboard_outlined, color: accentColor, size: 20),
            const SizedBox(width: 8),
            Text(
              'War Room',
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: accentColor,
          labelColor: accentColor,
          unselectedLabelColor:
              isDark ? const Color(0xFF71717A) : const Color(0xFF52525B),
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: 'Geist Sans',
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            fontFamily: 'Geist Sans',
          ),
          tabs: const [
            Tab(text: 'Fleet'),
            Tab(text: 'Mesh'),
            Tab(text: 'ThoxRoute'),
            Tab(text: 'Alerts'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _FleetTab(
            devices: devices,
            isDark: isDark,
            accentColor: accentColor,
            surfaceColor: surfaceColor,
            borderColor: borderColor,
          ),
          _MeshTab(
            nodes: nodes,
            isDark: isDark,
            accentColor: accentColor,
            surfaceColor: surfaceColor,
            borderColor: borderColor,
          ),
          _ThoxRouteTab(
            models: models,
            isDark: isDark,
            accentColor: accentColor,
            surfaceColor: surfaceColor,
            borderColor: borderColor,
          ),
          _AlertsTab(
            alerts: alerts,
            isDark: isDark,
            accentColor: accentColor,
            surfaceColor: surfaceColor,
            borderColor: borderColor,
          ),
        ],
      ),
    );
  }
}

// ─── Fleet Tab ──────────────────────────────────────────────────

class _FleetTab extends StatelessWidget {
  final List<FleetDevice> devices;
  final bool isDark;
  final Color accentColor;
  final Color surfaceColor;
  final Color borderColor;

  const _FleetTab({
    required this.devices,
    required this.isDark,
    required this.accentColor,
    required this.surfaceColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final onlineCount =
        devices.where((d) => d.status == FleetDeviceStatus.online).length;
    final totalCount = devices.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary metrics row
        Row(
          children: [
            _MetricCard(
              label: 'ONLINE',
              value: '$onlineCount/$totalCount',
              valueColor: const Color(0xFF22C55E),
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
            ),
            const SizedBox(width: 12),
            _MetricCard(
              label: 'AVG CPU',
              value: '${(devices.fold<double>(0, (a, d) => a + d.cpuUsage, ) / devices.length * 100).toStringAsFixed(0)}%',
              valueColor: accentColor,
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
            ),
            const SizedBox(width: 12),
            _MetricCard(
              label: 'AVG MEM',
              value: '${(devices.fold<double>(0, (a, d) => a + d.memoryUsage, ) / devices.length * 100).toStringAsFixed(0)}%',
              valueColor: const Color(0xFFF59E0B),
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'DEVICES',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamily: 'Geist Mono',
            color: isDark ? const Color(0xFF71717A) : const Color(0xFF52525B),
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        ...devices.map((d) => _FleetDeviceCard(
              device: d,
              isDark: isDark,
              accentColor: accentColor,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
            )),
      ],
    );
  }
}

class _FleetDeviceCard extends StatelessWidget {
  final FleetDevice device;
  final bool isDark;
  final Color accentColor;
  final Color surfaceColor;
  final Color borderColor;

  const _FleetDeviceCard({
    required this.device,
    required this.isDark,
    required this.accentColor,
    required this.surfaceColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16), // ThoxOS container radius
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: Border.all(color: Colors.transparent),
        title: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: device.status.statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Geist Sans',
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  Text(
                    '${device.ipAddress} · ${device.role.label}',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Geist Mono',
                      color: isDark
                          ? const Color(0xFF71717A)
                          : const Color(0xFF52525B),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: device.status.statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: device.status.statusColor.withValues(alpha: 0.5),
                  width: 0.5,
                ),
              ),
              child: Text(
                device.status.label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Geist Mono',
                  color: device.status.statusColor,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4, left: 20),
          child: Text(
            'CPU ${(device.cpuUsage * 100).toStringAsFixed(0)}% · MEM ${(device.memoryUsage * 100).toStringAsFixed(0)}% · DISK ${(device.diskUsage * 100).toStringAsFixed(0)}% · ${device.uptime.inDays}d ${device.uptime.inHours}h',
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'Geist Mono',
              color: isDark ? const Color(0xFF71717A) : const Color(0xFF52525B),
            ),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Usage bars
                _UsageBar(
                  label: 'CPU',
                  value: device.cpuUsage,
                  color: accentColor,
                  isDark: isDark,
                ),
                const SizedBox(height: 6),
                _UsageBar(
                  label: 'MEM',
                  value: device.memoryUsage,
                  color: const Color(0xFFF59E0B),
                  isDark: isDark,
                ),
                const SizedBox(height: 6),
                _UsageBar(
                  label: 'DISK',
                  value: device.diskUsage,
                  color: const Color(0xFF3B82F6),
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                Text(
                  'SERVICES (${device.services.length})',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Geist Mono',
                    color: isDark
                        ? const Color(0xFF71717A)
                        : const Color(0xFF52525B),
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 6),
                ...device.services.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: s.status.statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            s.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'Geist Mono',
                              color: isDark
                                  ? const Color(0xFFE4E4E7)
                                  : const Color(0xFF16161A),
                            ),
                          ),
                          if (s.version != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              'v${s.version}',
                              style: TextStyle(
                                fontSize: 10,
                                fontFamily: 'Geist Mono',
                                color: isDark
                                    ? const Color(0xFF71717A)
                                    : const Color(0xFF52525B),
                              ),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            ':${s.port}',
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'Geist Mono',
                              color: isDark
                                  ? const Color(0xFF52525B)
                                  : const Color(0xFF71717A),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            s.status.label,
                            style: TextStyle(
                              fontSize: 9,
                              fontFamily: 'Geist Mono',
                              color: s.status.statusColor,
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mesh Tab ───────────────────────────────────────────────────

class _MeshTab extends StatelessWidget {
  final List<MeshNode> nodes;
  final bool isDark;
  final Color accentColor;
  final Color surfaceColor;
  final Color borderColor;

  const _MeshTab({
    required this.nodes,
    required this.isDark,
    required this.accentColor,
    required this.surfaceColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final connectedCount = nodes
        .where((n) => n.status == MeshNodeStatus.connected)
        .length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            _MetricCard(
              label: 'CONNECTED',
              value: '$connectedCount/${nodes.length}',
              valueColor: accentColor,
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
            ),
            const SizedBox(width: 12),
            _MetricCard(
              label: 'BAUD',
              value: '921600',
              valueColor: const Color(0xFF3B82F6),
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
            ),
            const SizedBox(width: 12),
            _MetricCard(
              label: 'PROTOCOL',
              value: 'COBS',
              valueColor: const Color(0xFFA855F7),
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'MESH NODES',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamily: 'Geist Mono',
            color: isDark ? const Color(0xFF71717A) : const Color(0xFF52525B),
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        ...nodes.map((n) => _MeshNodeCard(
              node: n,
              isDark: isDark,
              accentColor: accentColor,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
            )),
      ],
    );
  }
}

class _MeshNodeCard extends StatelessWidget {
  final MeshNode node;
  final bool isDark;
  final Color accentColor;
  final Color surfaceColor;
  final Color borderColor;

  const _MeshNodeCard({
    required this.node,
    required this.isDark,
    required this.accentColor,
    required this.surfaceColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: node.status.statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  node.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Geist Sans',
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: node.status.statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: node.status.statusColor.withValues(alpha: 0.5),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  node.status.label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Geist Mono',
                    color: node.status.statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _InfoChip(
                label: 'TYPE',
                value: node.nodeType.name.toUpperCase(),
                isDark: isDark,
              ),
              const SizedBox(width: 12),
              _InfoChip(
                label: 'BAUD',
                value: '${node.baudRate}',
                isDark: isDark,
              ),
              const SizedBox(width: 12),
              _InfoChip(
                label: 'CRC ERR',
                value: '${node.crcErrors}',
                isDark: isDark,
                valueColor: node.crcErrors > 5
                    ? const Color(0xFFEF4444)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _InfoChip(
                label: 'TX',
                value: '${node.packetsSent}',
                isDark: isDark,
              ),
              const SizedBox(width: 12),
              _InfoChip(
                label: 'RX',
                value: '${node.packetsReceived}',
                isDark: isDark,
              ),
              const SizedBox(width: 12),
              _InfoChip(
                label: 'PROTO',
                value: node.protocol,
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── ThoxRoute Tab ──────────────────────────────────────────────

class _ThoxRouteTab extends StatelessWidget {
  final List<ThoxRouteModel> models;
  final bool isDark;
  final Color accentColor;
  final Color surfaceColor;
  final Color borderColor;

  const _ThoxRouteTab({
    required this.models,
    required this.isDark,
    required this.accentColor,
    required this.surfaceColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final available = models
        .where((m) => m.status == ThoxRouteStatus.available)
        .length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            _MetricCard(
              label: 'MODELS',
              value: '${models.length}',
              valueColor: accentColor,
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
            ),
            const SizedBox(width: 12),
            _MetricCard(
              label: 'AVAILABLE',
              value: '$available',
              valueColor: const Color(0xFF22C55E),
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
            ),
            const SizedBox(width: 12),
            _MetricCard(
              label: 'ENDPOINT',
              value: 'route.thox.ai',
              valueColor: const Color(0xFF3B82F6),
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'ROUTE MODELS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamily: 'Geist Mono',
            color: isDark ? const Color(0xFF71717A) : const Color(0xFF52525B),
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        ...models.map((m) => _ThoxRouteModelTile(
              model: m,
              isDark: isDark,
              accentColor: accentColor,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
            )),
      ],
    );
  }
}

class _ThoxRouteModelTile extends StatelessWidget {
  final ThoxRouteModel model;
  final bool isDark;
  final Color accentColor;
  final Color surfaceColor;
  final Color borderColor;

  const _ThoxRouteModelTile({
    required this.model,
    required this.isDark,
    required this.accentColor,
    required this.surfaceColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12), // ThoxOS control radius
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 32,
            decoration: BoxDecoration(
              color: model.category.accentColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      model.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Geist Mono',
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color:
                            model.category.accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        model.category.label,
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Geist Mono',
                          color: model.category.accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '${(model.contextWindow / 1000).toStringAsFixed(0)}K ctx',
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'Geist Mono',
                        color: isDark
                            ? const Color(0xFF71717A)
                            : const Color(0xFF52525B),
                      ),
                    ),
                    if (model.latencyMs != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${model.latencyMs}ms',
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'Geist Mono',
                          color: isDark
                              ? const Color(0xFF71717A)
                              : const Color(0xFF52525B),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: model.status.statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: model.status.statusColor.withValues(alpha: 0.5),
                width: 0.5,
              ),
            ),
            child: Text(
              model.status.label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                fontFamily: 'Geist Mono',
                color: model.status.statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Alerts Tab ─────────────────────────────────────────────────

class _AlertsTab extends StatelessWidget {
  final List<WarRoomAlert> alerts;
  final bool isDark;
  final Color accentColor;
  final Color surfaceColor;
  final Color borderColor;

  const _AlertsTab({
    required this.alerts,
    required this.isDark,
    required this.accentColor,
    required this.surfaceColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final critical = alerts
        .where((a) => a.severity == WarRoomAlertSeverity.critical)
        .length;
    final warnings = alerts
        .where((a) => a.severity == WarRoomAlertSeverity.warning)
        .length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            _MetricCard(
              label: 'CRITICAL',
              value: '$critical',
              valueColor: const Color(0xFFEF4444),
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
            ),
            const SizedBox(width: 12),
            _MetricCard(
              label: 'WARNINGS',
              value: '$warnings',
              valueColor: const Color(0xFFF59E0B),
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
            ),
            const SizedBox(width: 12),
            _MetricCard(
              label: 'TOTAL',
              value: '${alerts.length}',
              valueColor: accentColor,
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...alerts.map((a) => _AlertCard(
              alert: a,
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
            )),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  final WarRoomAlert alert;
  final bool isDark;
  final Color surfaceColor;
  final Color borderColor;

  const _AlertCard({
    required this.alert,
    required this.isDark,
    required this.surfaceColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: alert.severity.color.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: double.infinity,
            constraints: const BoxConstraints(minHeight: 40),
            decoration: BoxDecoration(
              color: alert.severity.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: alert.severity.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        alert.severity.label,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Geist Mono',
                          color: alert.severity.color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      alert.source,
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'Geist Mono',
                        color: isDark
                            ? const Color(0xFF71717A)
                            : const Color(0xFF52525B),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatTime(alert.timestamp),
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'Geist Mono',
                        color: isDark
                            ? const Color(0xFF52525B)
                            : const Color(0xFF71717A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  alert.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Geist Sans',
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                if (alert.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    alert.description!,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'Geist Sans',
                      height: 1.4,
                      color: isDark
                          ? const Color(0xFFA1A1AA)
                          : const Color(0xFF52525B),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ─── Shared widgets ─────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final bool isDark;
  final Color surfaceColor;
  final Color borderColor;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.isDark,
    required this.surfaceColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? Colors.black.withValues(alpha: 0.3) : surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 0.5),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                fontFamily: 'Geist Mono',
                color: isDark
                    ? const Color(0xFF71717A)
                    : const Color(0xFF52525B),
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontFamily: 'Geist Mono',
                color: valueColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageBar extends StatelessWidget {
  final String label;
  final double value; // 0.0 - 1.0
  final Color color;
  final bool isDark;

  const _UsageBar({
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'Geist Mono',
              color: isDark
                  ? const Color(0xFF71717A)
                  : const Color(0xFF52525B),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: value,
              color: color,
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(
            '${(value * 100).toStringAsFixed(0)}%',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'Geist Mono',
              color: isDark
                  ? const Color(0xFFA1A1AA)
                  : const Color(0xFF52525B),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  final Color? valueColor;

  const _InfoChip({
    required this.label,
    required this.value,
    required this.isDark,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            fontFamily: 'Geist Mono',
            color: isDark
                ? const Color(0xFF52525B)
                : const Color(0xFF71717A),
            letterSpacing: 0.8,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'Geist Mono',
            color: valueColor ??
                (isDark
                    ? const Color(0xFFE4E4E7)
                    : const Color(0xFF16161A)),
          ),
        ),
      ],
    );
  }
}
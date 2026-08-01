# ThoxWarRoom Architecture

## Overview

ThoxWarRoom is a native Flutter mobile client (iOS/Android) forked from Conduit (GPL-3.0), customized for THOX.ai LLC operations. It extends the original Open WebUI + Hermes Agent client with THOX technology integrations and the ThoxOS design system.

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter 3.9+ (Dart) |
| State Management | Riverpod 3 with generated providers |
| Navigation | GoRouter |
| HTTP/Realtime | Dio, socket_io_client |
| Local Storage | Drift (SQL), flutter_secure_storage, shared_preferences |
| Markdown | markdown package + custom Flutter renderer |
| Platform UI | adaptive_platform_ui, Cupertino + Material 3 |

## Component Map

### Core Layer (`lib/core/`)

- **auth/** — Multi-path authentication: Open WebUI (password, LDAP, JWT, SSO, proxy), Direct connections (API keys), Hermes Agent (server key)
- **database/** — Drift database with DAOs for chats, messages, notes, folders, outbox, search (FTS)
- **network/** — HTTP client (Dio), WebSocket transport, image caching with self-signed cert support
- **router/** — GoRouter with redirect logic for auth state
- **services/** — API service (6000+ lines covering all Open WebUI endpoints), sync engine, notifications, connectivity, settings
- **sync/** — Bidirectional sync: pull/push, outbox drainer, chat merger, deletion reconciliation

### Feature Layer (`lib/features/`)

- **auth/** — Server connection, authentication, SSO, proxy auth, backend chooser
- **chat/** — Chat page, streaming, voice mode, voice call, markdown rendering, model selector
- **channels/** — Channel threads and reactions
- **hermes/** — Hermes Agent sessions, jobs, tools, approval flow
- **navigation/** — Sidebar, drawer, folder pages, conversation list
- **notes/** — Note editor (Fleather), audio recording, AI enhancement
- **terminal/** — Interactive WebSocket terminal sessions
- **workspace/** — Models, knowledge bases, prompts, tools, skills management
- **warroom/** — THOX fleet/mesh/ThoxRoute dashboard (NEW)

### War Room Module (`lib/features/warroom/`)

The War Room is the THOX-specific extension providing infrastructure monitoring:

```
warroom/
├── models/
│   └── warroom_models.dart      # FleetDevice, MeshNode, ThoxRouteModel, WarRoomAlert
├── providers/
│   └── warroom_providers.dart   # Riverpod providers (30s refresh)
└── views/
    └── warroom_page.dart        # Tabbed dashboard: Fleet / Mesh / ThoxRoute / Alerts
```

#### Data Flow

```
THOX Fleet Devices ──→ /health endpoints ──→ FleetDevice model
                                              ↓
MeshCore Hub (C6) ──→ UART 921600 baud ──→ MeshNode model
                      COBS+CBOR+CRC32C        ↓
ThoxRoute API ─────→ /v1/models ──────→ ThoxRouteModel model
                                              ↓
                                    WarRoomStatus aggregate
                                              ↓
                                    WarRoomPage (TabBarView)
                                      ├── Fleet tab (device cards)
                                      ├── Mesh tab (node cards)
                                      ├── ThoxRoute tab (model tiles)
                                      └── Alerts tab (alert cards)
```

### Shared Layer (`lib/shared/`)

- **theme/** — ThoxOS theme (emerald accent, dark-first), TweakcnTheme system, color tokens, typography, button/input styles
- **widgets/** — Markdown renderer, streaming orbit, loading skeletons, responsive drawer, themed dialogs/sheets

## ThoxOS Design System Integration

The ThoxOS theme is implemented as a `TweakcnThemeVariant` in `lib/shared/theme/tweakcn_themes.dart`:

- **Dark variant**: True black (#000000) background, emerald-500 (#10B981) primary, gray-800 (#16161A) secondary, hairline borders (white/10)
- **Light variant**: Gray-50 (#FAFAFA) background, emerald-600 (#059669) primary, gray-200 borders
- **Radius**: 12px (matching ThoxOS control radius)
- **Status colors**: Success #22C55E, Warning #F59E0B, Danger #EF4444, Info #3B82F6, Agentic #A855F7

The ThoxOS theme is set as the default (`conduit = thoxos` alias), ensuring all users get the THOX.ai design system on first launch.

## THOX Fleet Topology

| Device | IP | Role | Key Services |
|--------|-----|------|-------------|
| KnightHub WSL2 | 100.97.135.46 | PRIMARY | hermes-agent, open-webui, thox-meshd, tailscale |
| Windows Host | 100.105.6.57 | FUNNEL | caddy-proxy, tailscale |
| MacBook Pro | 100.64.44.121 | SECONDARY | hermes-agent, obsidian-sync |
| HF Sentinel | cloud | SENTINEL | hf-endpoint (failover) |

## MeshCore Protocol

- Transport: UART at 921600 baud
- Framing: [0x00][COBS(CBOR+CRC32C_LE)][0x00]
- Implementation: thox-meshcore-c6 (C++) + thox-meshd (Rust)
- Key constraint: serde_cbor emits fields in declaration order — structs must match C++ canonical key order

## Build

```bash
flutter pub get
dart run build_runner build
flutter run -d ios     # or -d android
flutter test           # verification
flutter analyze        # lint
```

## License

GPL-3.0 (inherited from upstream Conduit)

Copyright (c) 2024-2026 THOX.ai LLC. All rights reserved.
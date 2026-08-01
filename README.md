<h1 align="center">ThoxWarRoom</h1>

<p align="center">
  <strong>THOX.ai LLC — War Room mobile command center for ThoxOS, MeshStack, and Hermes Agent operations.</strong>
</p>

<p align="center">
  <a href="https://github.com/ttracx/thoxwarroom">
    <img alt="Repository" src="https://img.shields.io/badge/repository-ttracx/thoxwarroom-0B1220" />
  </a>
  <img alt="THOX.ai LLC" src="https://img.shields.io/badge/owner-THOX.ai%20LLC-00A676" />
  <img alt="License" src="https://img.shields.io/badge/license-GPL--3.0-22c55e" />
  <img alt="CTO" src="https://img.shields.io/badge/CTO-Tommy%20Xaypanya-1F6FEB" />
  <img alt="CEO" src="https://img.shields.io/badge/CEO-Craig%20Ross-6F42C1" />
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#thoxos-design-system">Design System</a> ·
  <a href="#war-room-dashboard">War Room</a> ·
  <a href="#getting-started">Getting Started</a> ·
  <a href="#architecture">Architecture</a> ·
  <a href="#privacy">Privacy</a> ·
  <a href="docs/BUILDING.md">Build from Source</a>
</p>

<br>

ThoxWarRoom is a native Flutter mobile client forked from [Conduit](https://github.com/cogwheel0/conduit) (GPL-3.0), customized and extended for THOX.ai LLC operations. It connects to Open WebUI servers, direct model endpoints, and Hermes Agent instances — with integrated THOX technology monitoring:

- **ThoxRoute** — Model routing infrastructure (route.thox.ai/v1) with 12 workspace model categories
- **MeshStack / MeshCore** — Real-time mesh network node monitoring (COBS+CBOR+CRC32C protocol)
- **Fleet Monitoring** — THOX device fleet health (KnightHub WSL2, Windows Funnel, MacBook, HF Sentinel)
- **ThoxOS Design System** — Dark-first, emerald accent (#10B981), Chakra Petch typography

## Features

### Chat that survives mobile

Token-by-token streaming over WebSocket. Full conversation history, folders, search, pinning, temporary chats. Syntax-highlighted code blocks, Mermaid diagrams, LaTeX, reasoning sections, inline citations, and Chart.js embeds — all native Flutter.

### Three ways to connect

| | | |
| --- | --- | --- |
| **Open WebUI** | Your self-hosted server | Full feature set: chats, folders, notes, channels, workspace, tools, web search, image generation |
| **Direct** | OpenAI-compatible, Ollama, OpenRouter, ThoxRoute | Talk straight to a provider or model. No Open WebUI account required |
| **Hermes** | Your self-hosted agent | Agent tools, approval flow, scheduled jobs |

### War Room Dashboard

A dedicated tab providing real-time command-center visibility into THOX infrastructure:

- **Fleet tab** — Device status (online/degraded/offline), CPU/memory/disk usage bars, service health per device, container IDs and versions
- **Mesh tab** — MeshCore node connectivity, baud rate (921600), COBS+CBOR+CRC32C protocol stats, packet counts and CRC error tracking
- **ThoxRoute tab** — All 12 route models (auto, chat, reasoning, frontier, coder, vision, summarize, private, company, search, agentic, team) with context window, latency, and availability status
- **Alerts tab** — Severity-tiered alerts (critical/warning/info) with source attribution and timestamps

### Everything else

| Area | What's included |
| --- | --- |
| Files and media | Uploads, multimodal prompts, clipboard image paste, audio attachments |
| Notes | Autosave, pinning, AI titles, audio recording, offline |
| Channels | Threads and reactions |
| Voice | Voice input + full voice-call mode |
| Home screen | Widgets on iOS and Android, quick actions, App Intents |
| Sharing | Share-sheet ingestion |
| Terminal | Interactive WebSocket sessions |
| Personalization | Light, dark, and system themes; ThoxOS emerald accent palette; adaptive Material and Cupertino UI |
| Languages | 13 locales |

## ThoxOS Design System

ThoxWarRoom applies the THOX.ai design system from the [thoxos-webby-edition](https://github.com/ttracx/thoxos-webby-edition) reference repo:

- **Dark-first**: True black (#000000) root, gray-900 (#0B0B0C) surfaces
- **One accent**: Emerald-500 (#10B981) for focus, selection, active states, buttons
- **Typography**: Geist Sans (body), Geist Mono (metrics/values), with Chakra Petch available for display headings
- **Radius**: Controls 12px (rounded-lg), containers 16px (rounded-xl)
- **Borders**: Hairline — border-white/10 in dark, border-gray-200 in light
- **Status bar**: Emerald status pills, mono-font labels
- **No external references**: No font CDN, no analytics, no icon hosts

## Platforms

| Platform | Build | Installer |
| --- | --- | --- |
| iOS 16+ | `flutter build ios --release` | .ipa (App Store / TestFlight) |
| Android 7+ | `flutter build apk --release` | .apk / .aab (Google Play) |
| macOS 14+ | `flutter build macos --release` | .dmg (`scripts/create_dmg.sh`) |
| Windows 10+ | `flutter build windows --release` | .zip / .msix (`scripts/create_windows_installer.sh`) |

CI builds all four platforms on every tag push (`v*`).

## Getting Started

```bash
git clone --recursive https://github.com/ttracx/thoxwarroom.git
cd thoxwarroom
flutter pub get
dart run build_runner build
flutter run -d ios   # or: android, macos, windows
```

See **[docs/BUILDING.md](docs/BUILDING.md)** for full build instructions.

## Architecture

```
lib/
├── core/              # App-wide services, models, routing, auth, storage
│   ├── auth/          # Open WebUI, Direct, and Hermes auth flows
│   ├── database/      # Drift database, DAOs, FTS
│   ├── network/       # HTTP, WebSocket, image caching
│   ├── router/        # GoRouter configuration
│   └── services/      # API, sync, notifications, etc.
├── features/          # Product areas
│   ├── auth/          # Login, SSO, proxy auth
│   ├── automations/   # Scheduled prompts (cron-based) ← NEW
│   ├── chat/          # Chat UI, streaming, voice mode, context compaction ← NEW
│   ├── channels/      # Channel threads
│   ├── composer_shortcuts/  # @ model, / prompt, $ skill, # knowledge pickers ← NEW
│   ├── hermes/        # Hermes Agent sessions and jobs
│   ├── insights/      # Usage analytics dashboard ← NEW
│   ├── memories/      # AI memories CRUD ← NEW
│   ├── models/        # Model favorites & recents ← NEW
│   ├── navigation/    # Sidebar, drawer, folders
│   ├── notes/         # Note editor with audio
│   ├── spotlight/     # Desktop floating chat bar (macOS/Windows) ← NEW
│   ├── terminal/      # WebSocket terminal
│   ├── warroom/       # THOX fleet/mesh/ThoxRoute dashboard
│   ├── workspace/     # Models, knowledge, tools, skills
│   └── workspace_browser/  # Hermes file system browser ← NEW
├── shared/            # Reusable widgets and utilities
│   ├── theme/         # ThoxOS theme, color tokens, typography
│   └── widgets/       # Markdown, sheets, dialogs, loading
└── l10n/              # 13 locale ARB files
```

## New Features (v4.1)

Features incorporated from similar apps in the ecosystem:

### From Open Relay (native iOS Open WebUI client)
- **AI Memories** — view, add, edit, and delete AI memories that persist across conversations
- **Composer Shortcuts** — type `@` to switch model, `/` for prompts, `$` for skills, `#` for knowledge bases
- **Automations** — schedule prompts to run automatically at recurring times with cron expressions

### From Hermex (native iOS Hermes agent client)
- **Model Favorites & Recents** — star models for quick access, auto-track recently used
- **Usage Insights** — dashboard with prompt/token counts, daily activity chart, and model usage breakdown
- **Workspace File Browser** — explore your Hermes server's file system with search, syntax-highlighted viewer, and CRUD operations

### From Open WebUI Computer
- **Context Compaction** — long conversations automatically summarized to stay fast, keeping system prompt and recent messages intact
- **Workspace File Browser** — file management with search, upload, rename, delete

### From Open WebUI Desktop
- **Spotlight** — floating chat bar summoned with Shift+Cmd+I (macOS) or Shift+Ctrl+I (Windows). Type a prompt from anywhere, get instant AI responses without opening the full app
- **Desktop Support** — native macOS and Windows builds with adaptive window sizing, persistent sidebar, and keyboard shortcuts

### THOX Technology Integration

The `lib/features/warroom/` module adds THOX-specific infrastructure monitoring:

- **models/warroom_models.dart** — Data models for FleetDevice, MeshNode, ThoxRouteModel, WarRoomAlert
- **providers/warroom_providers.dart** — Riverpod providers with 30-second refresh cycle
- **views/warroom_page.dart** — Tabbed dashboard (Fleet / Mesh / ThoxRoute / Alerts) with ThoxOS styling

In production, the providers poll:
- Fleet: `http://<device>:8080/health` on each THOX device
- Mesh: `serial://` or `tcp://<mesh-hub>:9216` for MeshCore stats
- ThoxRoute: `https://route.thox.ai/v1/models` for model availability

## Privacy

- Chats, notes, and drafts are stored on-device. Notes stay available offline.
- Credentials use platform secure storage (Keychain/Keystore).
- No third-party analytics or advertising SDKs.
- No developer-operated backend relays data. Traffic goes from device to your configured server only.

## Acknowledgements

ThoxWarRoom is forked from [Conduit](https://github.com/cogwheel0/conduit) by cogwheel0, licensed under GPL-3.0. We gratefully acknowledge the original work and the Open WebUI community.

## Legal

Copyright (c) 2024-2026 THOX.ai LLC. All rights reserved.

**THOX.ai LLC**
- CTO: Tommy Xaypanya
- CEO: Craig Ross

ThoxWarRoom is licensed under the [GPL-3.0 License](LICENSE), inherited from the upstream Conduit project.

Unauthorized copying, modification, merger, publication, distribution, sublicensing, and/or selling of this software, via any medium, is strictly prohibited without prior written consent from THOX.ai LLC, except as permitted by the GPL-3.0 license terms.
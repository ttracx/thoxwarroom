# Current Service Contracts

Last captured: 2026-08-23

## Purpose and clean-room boundary

This document freezes the non-sensitive contracts that the native iOS and
macOS ThoxWarRoom clients may implement against. It was produced without
reading or copying the GPL `v4.1.0` ThoxWarRoom source.

Evidence is deliberately classified:

- **Observed live** means an unauthenticated request was sent to the public
  `https://webui.thox.ai` deployment and only its status, content type, and a
  sanitized response shape were retained.
- **Current source** means the contract is implemented in another current THOX
  repository at the exact revision named below. It is not evidence that a
  service is deployed or reachable from an Apple device.
- **Inferred** means a client design recommendation, not an established server
  contract.
- **Unverified** means authenticated or private live evidence is still needed.

No credentials, cookies, access tokens, prompts, document contents, internal
addresses, filesystem values, or live user/service records are recorded here.

## Contract sources

| Source | Revision/evidence | Use |
|---|---|---|
| ThoxWarRoom | `1e1bf52c84856f363e52be7f3cdfe9220493359e` (`main`) | Native app integration categories and security boundary |
| `webui.thox.ai` | Unauthenticated requests on 2026-08-23 | Public Open WebUI deployment behavior |
| Public Open WebUI bundle served by `webui.thox.ai` | Bundle reports version `0.11.0` | Client paths used by the deployed frontend |
| `ttracx/thox-digital-humans` | `5549da3adfa3b846274a332557868ce91816279e` (`main`, MIT) | Hermes dashboard and API-server contracts |
| `ttracx/THOX_MeshStack` | `02251d90b90728ce997423d31d4e2a78d9cd684e` (`origin/main`, proprietary THOX source) | Authenticated fleet, topology, and event contracts |

The sanitized live probe is checked in at
[`fixtures/current-service-contracts/openwebui-public-probe.sanitized.json`](fixtures/current-service-contracts/openwebui-public-probe.sanitized.json).

## 1. Open WebUI hosted surface

### Observed public endpoints

| Method | Path | Observed result | Safe response shape |
|---|---|---|---|
| `GET` | `/` | `200`, HTML | Application shell |
| `GET` | `/health` | `200`, text | `OK` |
| `GET` | `/api/version` | `200`, JSON | `version: string`; the deployment-specific identifier was intentionally discarded |
| `GET` | `/api/config` | `200`, JSON | `status`, `name`, `version`, `default_locale`, and `features` |
| `GET` | `/api/models` | `401`, JSON | `{ "detail": "Not authenticated" }` |
| `GET` | `/api/v1/auths/` | `401`, JSON | `{ "detail": "Not authenticated" }` |
| `GET` | `/api/v1/chats/` | `401`, JSON | `{ "detail": "Not authenticated" }` |
| `POST` | `/api/chat/completions` | `401`, JSON for an empty unauthenticated request | `{ "detail": "Not authenticated" }` |
| `POST` | `/api/v1/auths/signin` | `422`, JSON for `{}` | Validation requires `email` and `password` fields |

Observed `/api/config` feature values:

```json
{
  "status": true,
  "name": "THOX (Open WebUI)",
  "version": "0.11.0",
  "default_locale": "",
  "features": {
    "auth": true,
    "auth_trusted_header": false,
    "enable_signup_password_confirmation": false,
    "enable_ldap": false,
    "enable_signup": false,
    "enable_login_form": true,
    "enable_websocket": true
  }
}
```

`GET /openapi.json` and `GET /docs` both returned the application HTML rather
than an OpenAPI document. Therefore no public OpenAPI schema was available to
freeze.

### Paths visible in the deployed public client

The JavaScript bundle served by the live deployment defines these base paths:

- `/api/v1`
- `/api/models`
- `/api/chat/*`
- `/api/tasks/*`
- `/ollama`
- `/openai`
- `/api/v1/audio`
- `/api/v1/images`
- `/api/v1/retrieval`

The same bundle sends bearer authorization for protected model, chat, task,
pipeline, usage, event, and webhook requests. This is **current public-client
evidence**, but it does not prove the authenticated response DTOs used by this
particular deployment.

### Native Open WebUI adapter contract

The first native adapter should support only the following until an
authenticated contract capture is completed:

1. `GET /health` for reachability.
2. `GET /api/version` for compatibility gating.
3. `GET /api/config` for feature discovery and product labeling.
4. A protected `GET /api/models` probe to validate an already provisioned
   credential.
5. Protected chat and history operations only after their live request and
   response shapes are captured with a dedicated non-production test account.

Do not implement native password collection from the unauthenticated validation
response alone. The current WebView session is cookie-backed, while the public
bundle also uses bearer authorization for APIs; the supported token issuance,
refresh, revocation, and cookie-to-token handoff remain **unverified**.

## 2. Hermes Agent service

Hermes has two distinct transports. They must not be conflated in the native
client.

### 2.1 API-server transport (recommended native integration)

**Current source**, not live-deployment evidence. The API server advertises its
stable surface through authenticated `GET /v1/capabilities`.

| Method | Path | Purpose | Authentication |
|---|---|---|---|
| `GET` | `/health` and `/v1/health` | Basic liveness | Source permits unauthenticated access |
| `GET` | `/health/detailed` | Gateway/runtime status | Source permits unauthenticated access; treat returned process/runtime fields as sensitive and do not persist them by default |
| `GET` | `/v1/capabilities` | Discover features and endpoint paths | Bearer when an API key is configured |
| `GET` | `/v1/models` | OpenAI-compatible model list | Bearer when configured |
| `POST` | `/v1/chat/completions` | OpenAI-compatible chat, optional streaming | Bearer when configured |
| `POST` | `/v1/responses` | Responses-style stateful generation | Bearer when configured |
| `GET`, `DELETE` | `/v1/responses/{response_id}` | Read/delete a stored response | Bearer when configured |
| `POST` | `/v1/runs` | Start a structured agent run | Bearer when configured |
| `GET` | `/v1/runs/{run_id}` | Poll run state | Bearer when configured |
| `GET` | `/v1/runs/{run_id}/events` | Structured SSE lifecycle stream | Bearer when configured |
| `POST` | `/v1/runs/{run_id}/approval` | Resolve a pending approval | Bearer when configured |
| `POST` | `/v1/runs/{run_id}/stop` | Interrupt a run | Bearer when configured |

Source-defined capability facts:

- Runtime mode is `server_agent`; tool execution occurs on the server host.
- Run submission, polling, SSE, stop, approval responses, tool progress, and
  approval events are advertised.
- Optional continuity headers are `X-Hermes-Session-Id` and
  `X-Hermes-Session-Key`. Their values are credentials/session identifiers and
  must remain in Keychain-backed runtime state, never logs or fixtures.
- A network-accessible bind refuses startup without a configured API key.
- Chat and run request bodies are capped at 10 MB in current source.

#### Structured run request and response

`POST /v1/runs` accepts an object with:

- required `input`: a string or message array;
- optional `instructions`, `previous_response_id`, `conversation_history`,
  `session_id`, and `model`;
- optional session headers described above.

Success is `202`:

```json
{
  "run_id": "run_<opaque>",
  "status": "started"
}
```

The native app must treat the run identifier as opaque.

`GET /v1/runs/{run_id}/events` returns `text/event-stream`; each application
event is one `data: <JSON>` record. Current source emits these event names:

- `message.delta`
- `tool.started`
- `tool.completed`
- `reasoning.available`
- `approval.request`
- `approval.responded`
- `run.completed`
- `run.failed`
- `run.cancelled`

Unknown event names must be ignored safely and retained only as redacted audit
metadata. SSE comments are transport keepalives or stream-close markers, not
domain events.

An `approval.request` adds `run_id`, `timestamp`, and the choices `once`,
`session`, `always`, and `deny` to the approval payload. Resolve it with:

```http
POST /v1/runs/{run_id}/approval
Content-Type: application/json

{ "choice": "once|session|always|deny", "resolve_all": false }
```

Success shape:

```json
{
  "object": "hermes.run.approval_response",
  "run_id": "run_<opaque>",
  "choice": "once",
  "resolved": 1
}
```

`approve`, `approved`, and `allow` are accepted aliases for `once`, but the
native client should send canonical choices. `409` means the run has no active
or pending approval. A mutating approval action must be visibly confirmed and
written to the local audit store before transmission.

### 2.2 Hermes dashboard transport (not the first native adapter)

The dashboard is a local browser-oriented surface protected by an ephemeral
per-process session token. Protected HTTP routes use the
`X-Hermes-Session-Token` header; legacy bearer authorization is accepted.
WebSocket routes currently place the session token in the query string.

Relevant WebSockets:

| Path | Role |
|---|---|
| `/api/ws` | JSON-RPC sidecar |
| `/api/pty` | Raw PTY bytes for embedded terminal chat |
| `/api/events` | Passive structured event subscriber |
| `/api/pub` | Internal event publisher |

The JSON-RPC request envelope is
`{ "jsonrpc": "2.0", "id": <opaque>, "method": <string>, "params": <object> }`.
Events arrive as JSON-RPC notifications with method `event` and params shaped as
`{ "type", "session_id"?, "payload"? }`. `approval.respond` accepts the
session identifier, a canonical choice, and optional `all`.

This dashboard transport is unsuitable as the initial iOS/macOS service
contract because it is loopback/browser oriented, the session token is injected
into served HTML, embedded chat can be disabled, and `/api/pty` exposes terminal
semantics. Prefer the API-server run/SSE/approval transport.

## 3. War Room fleet, mesh, and alerts

**Current source**, not live-deployment evidence. Current MeshStack
`origin/main` provides the read-only data plane needed for the first War Room
slice:

| Method | Path | Result | Auth boundary |
|---|---|---|---|
| `GET` | `/api/admin/console/devices?mesh_id=<uuid>` | `{ data: Device[] }` | User bearer token; server checks mesh membership |
| `GET` | `/api/admin/console/topology?mesh_id=<uuid>` | `MeshTopology` | User bearer token; server checks mesh membership |
| `GET` | `/api/admin/console/events?mesh_id=<uuid>&limit=<1...500>` | `MeshEventsEnvelope` | User bearer token; server checks mesh membership |
| `GET` | `/api/topology?mesh_id=<uuid>` | `MeshTopology` | Mesh-authenticated user or device; server checks mesh access |
| `GET` | `/api/events?mesh_id=<uuid>` | `MeshEventsEnvelope` | Mesh-authenticated user or device; server checks mesh access |

`MeshTopology`:

```json
{
  "mesh_id": "<uuid>",
  "nodes": [
    {
      "id": "<uuid>",
      "display_name": "<string>",
      "role": "<enum-like string>",
      "platform": "<enum-like string>",
      "last_seen": "<timestamp|null>"
    }
  ],
  "edges": [
    {
      "source": "<uuid>",
      "target": "<uuid>",
      "rtt_ms": "<number|null>",
      "tunnel_active": "<boolean>"
    }
  ]
}
```

`MeshEventsEnvelope` contains `mesh_id`, `count`, and `data`; each event has
`id`, nullable `device_id`, `event_type`, `severity`, nullable `message`, and
`created_at`.

For MVP-03, map event severity to alerts locally. No separate current THOX
`/alerts` service contract was found, so an alerts endpoint would be an
unsupported invention. Do not implement pairing, device deletion, token
creation, or other control-plane writes in the read-only War Room slice.

## 4. Native adapter boundaries

The shared Swift package should expose four separate clients:

1. `OpenWebUIClient`: health, version, feature discovery, models, chat/history.
2. `HermesAPIClient`: capabilities, runs, SSE events, approvals, stop.
3. `MeshCoordinatorClient`: devices, topology, mesh events.
4. `WebSessionBridge`: existing cookie-backed `WKWebView` compatibility only;
   it must not silently share credentials with native clients.

Each workspace profile must declare service base URLs separately, store only
credential references in its profile, and keep credential material in
Keychain. A successful health check must not authorize fallback from a local or
private service to the hosted deployment.

## 5. Evidence still required

The following remain **unverified** and block claims of end-to-end native
readiness:

- An authenticated, non-production Open WebUI capture for model list, chat
  creation, chat history, streaming completion framing, citations, errors,
  token refresh, logout, and server-side revocation.
- A running private Hermes API-server capture of `/v1/capabilities`, a harmless
  run, SSE reconnect/cancellation, one denied approval, one one-time approval,
  and redacted error behavior.
- A running MeshStack coordinator capture using a test mesh, proving the user
  bearer path and DTOs for devices, topology, and events.
- TLS/trust behavior for LAN/private workspace profiles on physical iOS and
  macOS devices.
- An explicit retention policy for chat, run, event, and audit data.

No implementation should promote a source-defined or inferred contract to
"live verified" without these captures.

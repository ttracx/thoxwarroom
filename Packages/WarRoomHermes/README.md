# WarRoomHermes

Clean-room Swift models and transport client for the Hermes API-server contract
captured in `docs/current_service_contracts.md`. This package depends only on
`WarRoomCore` and Foundation. It does not implement networking, credential
storage, UI, or the browser-oriented dashboard/WebSocket transport.

## Supported contract

- `GET /v1/capabilities`
- `POST /v1/runs`
- `GET /v1/runs/{opaque-id}`
- `GET /v1/runs/{opaque-id}/events`
- `POST /v1/runs/{opaque-id}/approval`
- `POST /v1/runs/{opaque-id}/stop`

The caller injects a `WarRoomCore.ProviderTransport`, validated endpoint, and
optional in-memory credential. Request and response bodies are capped at 10 MB.
SSE parsing is incremental, cancellation-aware, and separately caps individual
events. `HermesAPIClient.events()` is nevertheless **buffered** because the
current `ProviderTransport` returns one complete response body. A streaming
transport seam and live reconnect behavior remain follow-up work and are not
claimed here. Comments are ignored. Unknown event payloads are discarded; only
a bounded safe event name may reach audit metadata.

The exact capabilities schema and stop response are not live-verified. Their
models intentionally accept only conservative optional/bounded structures and
must not be treated as proof that a capability is authorized or deployed.

## Approval and audit requirements

`approval.request` is a proposal, never authorization. `approve()` must sit
behind a UI confirmation plus durable audit/policy use case before any app
integration. Before calling it, the app must:

1. Render the requested action as untrusted content.
2. Require visible human confirmation for the exact run and scope.
3. Write a redacted local audit event before transmission.
4. Send only `once`, `session`, `always`, or `deny`; aliases are never emitted.
5. Treat HTTP 409 as no active/pending approval and do not retry as success.

Stopping a run is also a mutating action and needs an audit record. Run IDs are
opaque routing values: never parse identity or authorization from their text,
and never log their raw values. Session continuity headers remain outside this
package until a Keychain-backed runtime design is implemented.

## Test

```bash
cd Packages/WarRoomHermes
swift test
```

Tests use an in-memory `ProviderTransport` and sanitized fixtures. They make no
network requests.

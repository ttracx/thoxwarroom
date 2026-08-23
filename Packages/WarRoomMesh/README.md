# WarRoomMesh

Read-only MeshStack provider for native ThoxWarRoom clients. It depends on
`WarRoomCore` and executes only through a caller-supplied `ProviderTransport`.

## Scope

- user-authenticated device list for one validated mesh UUID;
- user-authenticated topology for the same mesh;
- user-authenticated event history with a validated `1...500` limit;
- typed DTO and contract-invariant validation;
- provenance, evidence strength, network-boundary, capture-time, and staleness
  metadata on every successful snapshot;
- bounded JSON decoding and cancellation propagation;
- offline tests with synthetic UUIDs and records.

`MeshProvider.descriptor` advertises only `warRoomStatus`. This package has no
pairing, device deletion, token creation, heartbeat, tunnel, or other mutation
API. It does not invent a separate alerts endpoint; callers may project alert
UI locally from read-only event severity.

## Evidence boundary

The route and DTO contracts are current-source evidence recorded in
`docs/current_service_contracts.md`; they have not been verified against a
running private coordinator. Snapshots therefore carry
`currentSourceNotLiveVerified` provenance. Test fixtures are synthetic and do
not contain identifiers or data from live records.

Underlying transport messages and provider bodies never enter typed public
errors. Credentials remain opaque and are forwarded only to the transport.

## Test

```bash
swift test --package-path Packages/WarRoomMesh
```

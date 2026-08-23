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

### Offline private-coordinator evidence gate

`mesh-contract-evidence` validates a sanitized capture bundle without making a
network request. Its ten requirements independently cover the user-bearer
credential boundary, sanctioned test identity and mesh membership, devices,
topology, events, partial/freshness provenance, authentication and authorization
failures, cancellation, and network failures. It has no mutation or capture
command.

Artifacts are confined to the manifest directory. The validator accepts only
bounded UTF-8 text/JSON, verifies declared byte counts and SHA-256 digests, and
rejects traversal, symlinks, binary content, unsupported media, and common
credential, token, session, or private-identity fields. Artifact contents and
credentials are never echoed in errors.

The checked-in manifest is intentionally truthful: all requirements are
`missing` because no sanctioned authenticated private coordinator, dedicated
test user, and test mesh capture is available. `audit` verifies that state and
exits successfully; `qualify` fails closed until all ten requirements have
sanitized artifacts:

```bash
cd Packages/WarRoomMesh
swift run mesh-contract-evidence audit Evidence/private-coordinator/current.manifest.json
swift run mesh-contract-evidence qualify Evidence/private-coordinator/current.manifest.json
```

Capture artifacts must come from a dedicated non-production coordinator using
an explicitly sanctioned test identity and test mesh. Never reuse a production
bearer, real user, real mesh membership, device identity, or live event payload.
Replace sensitive values before placing an artifact in the fixed evidence root,
then record its exact byte count and lowercase SHA-256 digest. A partially
captured bundle remains useful in `audit` mode but never passes `qualify`.

## Test

```bash
cd Packages/WarRoomMesh
swift test -Xswiftc -warnings-as-errors
```

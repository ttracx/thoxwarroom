# WarRoomOpenWebUI

Clean-room Swift provider for the small Open WebUI contract currently captured
by ThoxWarRoom. It depends only on `WarRoomCore` and performs network work
through the caller-supplied `ProviderTransport` seam.

## Implemented

- `GET /health`
- `GET /api/version`
- `GET /api/config`
- capability-gated `GET /api/models`
- typed DTOs and non-sensitive errors
- response-size checks before text or JSON decoding
- cancellation propagation
- an executable, fail-closed native-chat evidence gate
- an offline authenticated-contract evidence manifest auditor/qualifier
- fully offline transport-double tests

`OpenWebUIProvider.descriptor` advertises only `modelCatalog`. The package does
not claim chat, streaming, history, citations, or native authentication support.

## Evidence boundary

Public unauthenticated responses for health, version, configuration, and the
authentication boundary were observed on 2026-08-23 and are represented by the
sanitized test fixtures. The deployment-specific identifier and OAuth
configuration were deliberately omitted.

The authenticated `/api/models` response was not observed. Its fixture is
explicitly synthetic, and the provisional decoder accepts only a conservative
`{ "data": [{ "id": ..., "name": ...? }] }` envelope. A mismatch fails with
`OpenWebUIProviderError.decodingFailed`; it does not guess or fall back to an
untyped payload.

Still unverified and intentionally absent:

- password collection or sign-in;
- credential issuance, refresh, revocation, or cookie-to-token handoff;
- chat creation, chat history, completions, streaming, and citations;
- any live authenticated response fixture.

`OpenWebUIProvider.nativeChatContract` exposes the stable
`authenticated_capture_required` blocker and the exact missing evidence set.
The provider descriptor derives chat capabilities from that gate, so route-only
or unauthenticated evidence cannot accidentally enable native chat. The
sanitized `native-chat-boundary` fixture verifies the observed `401` route
boundaries while explicitly retaining no credential, prompt, response, or user
data.

The checked-in `Evidence/native-chat/current.manifest.json` is the executable
record of that boundary. It deliberately marks all authenticated elements
missing. Audit it without making a network request:

```bash
swift run --package-path Packages/WarRoomOpenWebUI \
  openwebui-contract-evidence audit \
  Packages/WarRoomOpenWebUI/Evidence/native-chat/current.manifest.json
```

After one sanctioned capture session with a dedicated non-production account
and synthetic prompt, place only sanitized text artifacts beside the manifest,
record their byte counts and SHA-256 digests, mark the supported requirements
`captured`, then run the same command with `qualify`. Qualification fails until
all nine requirements are present. The validator rejects absolute/traversing
paths, symlinks, non-text data, unsupported media types, oversized artifacts,
hash/size mismatches, incomplete requirement sets, common live credential
forms, and any manifest that claims sensitive values were retained. It never
contacts the service and does not infer any route or payload shape.

Credentials are opaque `ProviderCredential` values and are forwarded only to
the protected model request. Public health, version, and configuration probes
never receive them. Provider response bodies and underlying transport errors
are not included in public errors.

## Test

```bash
swift test --package-path Packages/WarRoomOpenWebUI
```

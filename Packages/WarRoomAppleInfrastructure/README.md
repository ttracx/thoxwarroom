# WarRoomAppleInfrastructure

Apple-platform implementations of the persistence and transport seams defined by
`WarRoomCore`. The package depends only on `WarRoomCore` and Apple system frameworks.

## Keychain credential vault

`KeychainCredentialVault` stores one generic-password item per workspace. The
service is fixed to `ai.thox.warroom.provider-credentials`; each account includes
the workspace UUID. Items explicitly disable synchronization and use
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. This stricter-than-after-first-
unlock default keeps credentials unavailable while a device is locked and prevents
migration through iCloud Keychain.

Store operations update existing items, add absent items, and retry update if an
add races with another writer. Reads and deletes are workspace-scoped. Deletion is
idempotent. Errors are typed and never contain credential bytes.

## Scoped provider transport

`URLSessionProviderTransport` creates an ephemeral session per request with cookies
and caching disabled. It constructs destinations exclusively from a
`ValidatedEndpoint` and a validated relative `ProviderRequest`; callers cannot add
an arbitrary host or headers. Bearer credentials are read only while constructing
the request and are never persisted or described.

The transport:

- limits request and streamed response body sizes;
- applies request and resource timeouts;
- accepts redirects only within the endpoint's exact scheme, host, and effective port;
- cancels and reports cross-origin redirects;
- validates HTTP responses and maps network failures to typed errors;
- checks task cancellation while consuming response bytes.

Same-origin redirect enforcement prevents a credential-bearing request from being
redirected to another boundary. A future live transport audit must additionally
verify resolved addresses on every connection to prevent DNS rebinding and define
certificate pinning/private-CA policy where deployments require it.

## Validate

```bash
cd Packages/WarRoomAppleInfrastructure
swift test
```

Tests use an injected Keychain client and custom `URLProtocol`; they do not alter a
developer's real Keychain or contact a network service.

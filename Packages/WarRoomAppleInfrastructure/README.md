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

## Encrypted workspace data

`EncryptedWorkspaceRecordCodec` seals bounded payloads with CryptoKit AES-256-GCM.
Each workspace has an independent 256-bit master key in a non-synchronizing
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` Keychain item. HKDF-SHA256 derives
a purpose key for each workspace, collection, and record. Authenticated additional
data binds those routing values plus the fixed algorithm, key reference, and
canonical millisecond creation/update timestamps. Moving or modifying any of that
metadata therefore fails authentication.

Key creation is intentionally separate from sealing. Callers must prove a workspace
has no existing ciphertext before calling `provisionMasterKey(for:)`; ordinary
`seal` operations never create a missing replacement key. This prevents an absent
Keychain item from silently making existing ciphertext unrecoverable. Explicit,
idempotent `deleteMasterKey(for:)` supports cryptographic workspace deletion after
provider credentials have been removed.

`EncryptedWorkspaceFileDataStore` implements Core's ciphertext-only store inside
the app container's Application Support directory. It uses only validated UUID and
collection components, rejects symlinked directories/final files, bounds reads with
`FileHandle` rather than file-size or timestamp metadata, and writes a same-directory
temporary file before `fsync` and atomic rename. Directories use mode `0700`, files
use `0600`, records are excluded from backup, and iOS temporary files receive
complete file protection before commit. Corrupt and oversized records fail closed
without being deleted; public errors never include paths, plaintext, keys, or
ciphertext.

The current foundation deliberately does not provide a default
`WorkspaceProfileStore`. A safe profile adapter must receive an injected, Sendable
provider-policy codec/resolver from the app and reconstruct capabilities from
current trusted policy. Persisted provider capability sets must never be decoded
and reused as authorization. Durable audit persistence remains a separate follow-up
on top of the same encrypted-record primitive.

### Security limitations

- `ThisDeviceOnly` keys do not migrate to another device; copied/restored ciphertext
  is intentionally unrecoverable without an explicit future export design.
- macOS does not provide the same locked-device file-protection semantics as iOS;
  macOS protection is AES-GCM plus Keychain access, sandbox containment, and POSIX
  permissions.
- The package does not claim rollback detection for replay of an older, otherwise
  valid authenticated record.
- Simulator and unit tests cannot prove physical-device lock-state behavior or
  production signing/entitlement behavior.

# WarRoomCore

`WarRoomCore` is the clean-room, platform-neutral foundation for the native
ThoxWarRoom iOS and macOS apps. It performs no network calls and provides no
credential or profile persistence.

## Included in WR-002

- validated workspace profiles with stable workspace and provider identities;
- explicit `localMachine`, `privateNetwork`, and `hosted` boundaries;
- URL validation for scheme, host, credentials, traversal, query/fragment, and
  explicit ports;
- explicit hosted-provider authorization and opt-in private HTTP/non-default ports;
- provider capability declarations used to gate features;
- audit events that irreversibly redact sensitive and secret-named fields before
  they reach a persistence seam;
- bounded, explicitly confirmed workspace audit-retention policies with
  compare-and-swap persistence, monotonic application timestamps, and no implied
  policy when a record is absent;
- an explicit lifecycle coordinator that validates retention results before
  recording application and never applies retention during policy lookup or save;
- `Sendable` protocols for profile storage, credential vaults, provider transport,
  and audit recording so later slices can be tested with in-memory implementations.

## Security boundary

Endpoint classification is syntactic and deliberately does not resolve DNS. A
future transport must re-check the resolved address at connection time to prevent
DNS rebinding and must apply certificate policy before sending credentials. A
validated endpoint does not establish trust or connectivity.

`ProviderCredential` only prevents accidental disclosure through `description`;
it is not secure memory. The future Keychain implementation must minimize copies,
apply workspace-scoped access controls, and never include credential bytes in logs
or audit events.

## Validate

```bash
cd Packages/WarRoomCore
swift test
```

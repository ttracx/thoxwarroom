# ThoxWarRoom Security Model

Last updated: 2026-08-23

## Assets

Credentials, session cookies, prompts, messages, documents, embeddings, model outputs, Hermes tool requests/results, fleet identifiers, device status, file paths, audit events, and release signing material.

## Trust boundaries

1. SwiftUI/platform UI to shared domain use cases.
2. Shared core to local encrypted storage and Keychain.
3. Transport adapter to each configured workspace endpoint.
4. Hermes proposal to policy/approval and then execution.
5. Main app to iOS extensions or macOS auxiliary windows.
6. Developer/release environment to Apple and GitHub signing systems.

## Primary threats and mitigations

| Threat | Required mitigation |
|---|---|
| Silent sensitive-data transfer | No implicit cloud fallback; visible workspace boundary; egress allowlist tests |
| Credential/session disclosure | Keychain; redact logs; explicit sign-out and data purge; no credentials in URLs |
| Malicious redirects/custom schemes | Require allowed schemes and normalized hosts; callback allowlist; block credentials in URL authority |
| Prompt/tool-output injection | Treat content as untrusted; never convert rendered text directly into tool authorization |
| Unauthorized Hermes action | Capability checks, least privilege, explicit approval, expiry, replay protection, append-only audit |
| Workspace file traversal | Canonicalize paths, enforce configured roots, reject symlink escape, read-only MVP |
| Cross-workspace data leakage | Workspace-scoped stores, caches, cookies, search indexes, and audit identifiers |
| Lost/stolen device | Platform data protection, encrypted local database, biometric/admin policy where required |
| Compromised dependency/build | Minimal dependencies, pinned actions/packages, SBOM, reproducible CI, signed provenance |
| Sensitive diagnostic logs | Structured event allowlist, redaction tests, user-controlled export |
| Incompatible source reuse | License inventory and owner/legal gate before using GPL-derived implementation in MIT code |

## Authentication and authorization

- Store tokens, keys, and sensitive session material in Keychain with the narrowest practical accessibility class.
- Model roles and capabilities independently of UI visibility.
- Re-authenticate or require explicit approval for high-impact actions.
- Never infer authorization from possession of an unvalidated deep link.

## Storage and retention

- Use a workspace-scoped encrypted store for chats, documents, settings, and audit data.
- Make retention, deletion, export, and cache clearing explicit.
- Use separate `WKWebsiteDataStore` boundaries if web compatibility remains during migration.
- Do not enable iCloud synchronization for sensitive stores by default.

## Audit logging

Record authentication outcomes, workspace/profile changes, Hermes approvals/denials, tool execution results, file mutations, automation changes, export/deletion, and policy failures. Do not record secrets, full prompts, full documents, or unrestricted tool output by default.

## Current known risks

- The current app is hosted-endpoint-only and uses the default persistent website data store.
- Navigation policy checks only the host.
- There is no explicit local audit store, RBAC, workspace isolation, privacy manifest, or verified deletion workflow.
- Signing, notarization, TestFlight, and clean-device behavior are not yet proven.
- The published v4.2 macOS app is a development-signed preview rejected by Gatekeeper, not a production distribution.

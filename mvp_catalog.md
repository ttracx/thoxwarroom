# ThoxWarRoom MVP Catalog

Priority uses `(Market Value × 0.40) + (Technical Feasibility × 0.30) + (Time-to-Market × 0.20) + (Strategic Importance × 0.10)` with each input scored 1–10.

| MVP | Problem solved | User | MV | TF | TTM | SI | Priority | Required modules | Success criteria | Key risk | Status |
|---|---|---|---:|---:|---:|---:|---:|---|---|---|---|
| Secure Workspace Foundation | Safely connect Apple apps to local/private THOX services | Admin/operator | 10 | 8 | 8 | 10 | 9.0 | Identity, Keychain, transport, trust, audit | Add/test/remove a private endpoint; secrets never logged; boundary visible | TLS and auth contract drift | In progress: provider and credential lifecycle wired; live private endpoint pending |
| Private Chat Vertical Slice | Native, resilient chat with a chosen local/private model | Knowledge worker | 10 | 7 | 7 | 10 | 8.5 | Chat, streaming, persistence, citations | Authenticated stream, cancel/retry, relaunch history, source display | Backend compatibility | In progress: discovery/model adapter only |
| Hermes Review Console | Observe sessions/jobs and approve or deny tools | Operator/approver | 10 | 7 | 6 | 10 | 8.3 | Hermes adapter, approval UI, audit | Live session stream; explicit approval; durable audit event | Unsafe action execution | In progress: credential-gated read-only buffered review; no actions |
| War Room Read-only Dashboard | See fleet, mesh, routes, and alerts in one place | Operator | 9 | 8 | 7 | 9 | 8.3 | War Room adapters, cache, status UI | Real endpoints, stale/error states, provenance and timestamps | Inconsistent device APIs | In progress: native read-only Mesh dashboard complete against synthetic fixtures; live evidence pending |
| Workspace Browser | Safely inspect private agent files | Developer/operator | 8 | 7 | 7 | 9 | 7.6 | File API, path policy, viewer | Read-only browse/search with root confinement | Path traversal/data exposure | Planned |
| Native Platform Productivity | Make iPhone/Mac workflows fast | Power user | 8 | 7 | 6 | 8 | 7.3 | Share extension, App Intents, Spotlight | Platform workflows complete without bypassing review | Extension credential/data sharing | Planned |
| Automations and Mutating Workspace | Controlled scheduled/action workflows | Approver/admin | 8 | 5 | 4 | 9 | 6.4 | Scheduler, RBAC, approval, audit | Create/disable/run with preview, policy, and audit | High-impact autonomous actions | Backlog |
| Signed Apple Release | Reproducible TestFlight and notarized Mac delivery | All users | 10 | 6 | 6 | 10 | 8.0 | CI, signing, privacy manifest, release docs | TestFlight install and notarized DMG pass clean-device smoke | Owner credentials/cert limits | In progress: signed IPA exported; ASC record and Developer ID unavailable |

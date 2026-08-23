# App Store Connect Metadata

Last source review: 2026-08-23

This file is a release worksheet, not evidence that Apple has accepted an app
record, build, privacy answer, export-compliance answer, or review submission.
Values marked **owner decision** must not be guessed during upload.

## New app record

| Field | Proposed value | Evidence/status |
|---|---|---|
| Platforms | iOS and macOS | Product goal and shared bundle ID; select both only if THOX wants one multi-platform record |
| Name | ThoxWarRoom | Current product and bundle display name; within Apple's 30-character limit |
| Primary language | English (U.S.) | **Owner decision** before record creation |
| Bundle ID | `ai.thox.warroom` | Registered identifier and signed archive evidence |
| SKU | `THOXWARROOM-APPLE-2026` | **Owner decision**; internal identifier should be treated as permanent |
| User access | Full Access | **Owner decision**; use Limited Access if app-scoped staff restrictions are required |
| Developer name | THOX AI LLC | Account-controlled value; confirm in the website |

Apple requires the app record before the first build upload. The website action
requires Account Holder, Admin, or App Manager access, and the Account Holder
must have accepted the latest agreement.

## Current build identity

| Property | Value |
|---|---|
| Marketing version | `4.2.0` |
| Build number | `2` |
| Bundle ID | `ai.thox.warroom` |
| Team | THOX AI LLC (`DVJ6Z5343U`) |
| iOS minimum | iOS 17 |
| macOS minimum | macOS 14 |
| iOS device family | iPhone |

Every accepted upload must use a build number not previously accepted for the
same version. Increment `CURRENT_PROJECT_VERSION` before a replacement upload
after Apple accepts build 2.

## TestFlight beta draft

### Beta description

ThoxWarRoom is the native THOX command center for explicitly configured local
or private AI workspaces. This beta covers encrypted workspace setup,
workspace-scoped credentials, Open WebUI discovery and model catalog, read-only
Hermes run review, read-only MeshStack status, and local audit-storage controls.

Authenticated native chat, Hermes approval/stop actions, and hosted WebView
compatibility are intentionally unavailable until their contracts and privacy
boundaries are verified.

### What to test

1. Create local-device and private-network workspaces and confirm the displayed
   endpoint/boundary before connecting.
2. Relaunch and confirm the selected workspace remains available while secrets
   are never displayed.
3. Add/remove a provider credential and confirm removal does not claim to revoke
   server-side access.
4. Load Open WebUI discovery/models, a Hermes read-only run, or a MeshStack
   read-only dashboard only against a sanctioned test endpoint.
5. Exercise offline, cancellation, invalid credential, empty, stale, and partial
   states. Do not use production PHI, PII, privileged documents, or live secrets
   in this pre-release build.

## Submission fields still requiring evidence or owner input

- App Store Connect owner/admin authentication and latest-agreement status.
- Final choice of platforms, primary language, SKU, and user-access scope.
- Support URL candidate: `https://www.thox.ai/help` (live HTTPS help center
  verified 2026-08-23; owner must confirm it is the intended app support page).
- Privacy-policy URL candidate: `https://www.thox.ai/privacy` (live HTTPS policy
  verified 2026-08-23; owner/legal must confirm its January 1, 2025 text covers
  this app and every enabled local, private-network, and optional hosted flow).
- App privacy answers covering every platform and any optional hosted service
  that is enabled in the submitted binary.
- Export-compliance determination for direct CryptoKit AES-256-GCM use and TLS;
  this requires owner/legal review and must not be inferred from a build pass.
- Age rating, categories, content rights, regional availability, DSA/trader
  status where applicable, review contact, and review notes.
- Screenshots captured from the exact submitted binary on required device sizes.
- TestFlight internal/external tester groups and beta review information.
- macOS distribution choice: Mac App Store/TestFlight build or separately
  notarized Developer ID DMG. The current macOS script implements the latter.

## Evidence boundaries

- A signed IPA proves local signing/export only.
- A successful upload proves transfer, not Apple processing or installability.
- `Processing` is not `Complete`; warnings must be reviewed even after completion.
- Simulator and package tests do not prove physical-device Keychain, file
  protection, local-network permission, accessibility, or provider behavior.
- The source privacy manifest does not replace App Store Connect privacy answers
  or a public privacy policy.

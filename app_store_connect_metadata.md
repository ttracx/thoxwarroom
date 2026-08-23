# App Store Connect Metadata

Last source review: 2026-08-23

This file records the selected App Store Connect metadata and the fields still
required for App Store/external-TestFlight review. Processing and distribution
evidence is retained separately in `release_evidence.md`.

## New app record

| Field | Proposed value | Evidence/status |
|---|---|---|
| Platforms | iOS and macOS | Created in shared App Store Connect record `6804445585` |
| Name | ThoxWarRoom | Created value; within Apple's 30-character limit |
| Primary language | English (U.S.) | Created as `en-US` |
| Bundle ID | `ai.thox.warroom` | Registered identifier and signed archive evidence |
| SKU | `THOXWARROOM-APPLE-2026` | Created value; treat as permanent |
| User access | Full Access | Created value |
| Developer name | THOX AI LLC | Account-controlled value; confirm in the website |

The shared record exists under THOX AI LLC. iOS and macOS build 3 are valid,
`IN_BETA_TESTING`, and assigned to the `THOX AI LLC Internal` TestFlight group.
Build 2 remains assigned as prior evidence. The single tester is still invited;
invitation acceptance and physical install/launch are not observed. Build 4 is
the current locally validated source candidate and is not claimed delivered
until separate App Store Connect processing evidence is recorded.

## Current build identity

| Property | Value |
|---|---|
| Marketing version | `4.2.0` |
| Build number | `4` (source candidate; build 3 remains the latest accepted delivery) |
| Bundle ID | `ai.thox.warroom` |
| Team | THOX AI LLC (`DVJ6Z5343U`) |
| iOS minimum | iOS 17 |
| macOS minimum | macOS 14 |
| iOS device family | iPhone |

Every accepted upload must use a build number not previously accepted for the
same version. `CURRENT_PROJECT_VERSION` is now `4`; increment it to `5` before
any replacement upload after Apple accepts build 4.

## TestFlight beta draft

### Beta description

ThoxWarRoom is the native THOX command center for explicitly configured local
or private AI workspaces. This beta covers encrypted workspace setup,
workspace-scoped credentials, Open WebUI discovery and model catalog, read-only
Hermes run review and reconciliation, read-only MeshStack status, and explicit
encrypted audit-policy, retention, and redacted-export controls.

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

- Latest-agreement status before an App Store or external-beta review submission.
- Support URL candidate: `https://www.thox.ai/help` (live HTTPS help center
  verified 2026-08-23; owner must confirm it is the intended app support page).
- Privacy-policy URL candidate: `https://www.thox.ai/privacy` (live HTTPS policy
  verified 2026-08-23; owner/legal must confirm its January 1, 2025 text covers
  this app and every enabled local, private-network, and optional hosted flow).
- App privacy answers covering every platform and any optional hosted service
  that is enabled in the submitted binary.
- Export compliance is recorded as no non-exempt encryption for the current
  Apple CryptoKit/OS-provided cryptography path. Owner/legal must re-review this
  classification if cryptographic code, use case, jurisdictions, or distribution change.
- Age rating, categories, content rights, regional availability, DSA/trader
  status where applicable, review contact, and review notes.
- Screenshots captured from the exact submitted binary on required device sizes.
- Internal group exists with both builds and `tommy@thox.ai` invited. External
  beta review information and invitation acceptance/physical install evidence remain.
- macOS distribution choice: the Mac App Store/TestFlight archive/export path
  and separate notarized Developer ID DMG path are both implemented. The owner
  must choose whether both are distributed and complete the corresponding Apple
  record/certificate gates.

## Evidence boundaries

- A signed IPA proves local signing/export only.
- A successful upload proves transfer, not Apple processing or installability.
- `Processing` is not `Complete`; warnings must be reviewed even after completion.
- Simulator and package tests do not prove physical-device Keychain, file
  protection, local-network permission, accessibility, or provider behavior.
- The source privacy manifest does not replace App Store Connect privacy answers
  or a public privacy policy.

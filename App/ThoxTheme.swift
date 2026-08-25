// ThoxTheme.swift
// THOX brand tokens — dark-first, emerald-accented, terminal-inspired.
//
// SOURCE OF TRUTH
// ---------------
// These values are the fleet-canonical THOX palette. They are transcribed from,
// and must stay identical to, three independently owned surfaces:
//
//   1. The THOX brand system (`brand-primary #10B981`, `brand-light #34D399`,
//      `brand-deep #059669`, `text-primary #FAFAFA`).
//   2. The ThoxMythos-9B product chat UI
//      (`web/app/globals.css` → `--thox-bg #09090b`, `--thox-surface #18181b`,
//      `--thox-elevated #27272a`, `--thox-border-strong #3f3f46`,
//      `--thox-muted #a1a1aa`, `--thox-faint #71717a`, `--thox-neon #00ff88`).
//   3. `thoxos-ios` → `Sources/ThoxDesign/ThoxTokens.swift` (generated).
//
// HISTORY: this file previously carried a fork of the palette (accent
// `#05A451`, background `#0C0E12`, surface `#161A20`) that matched neither the
// brand system nor any shipping THOX surface. That drift is corrected here.
// The static `chat-ux-golden.html` fixture still carries the old hexes because
// it is a frozen wire/interaction fixture, not a color authority — see
// `docs/CHAT_UX_STANDARD.md`.
//
// Member names are additive: every symbol that existed before still exists with
// the same name and role, so no call site changes.

import SwiftUI

enum ThoxTheme {
    // MARK: - Brand

    /// THOX emerald (brand-primary, emerald-500). Primary actions and accents.
    static let accent = Color(hex6: 0x10B981)

    /// Hover / highlight emerald (brand-light, emerald-400).
    static let accentLight = Color(hex6: 0x34D399)

    /// Active / pressed emerald (brand-deep, emerald-600).
    static let accentDeep = Color(hex6: 0x059669)

    /// High-energy terminal green, reserved for hover on already-accented text.
    static let neon = Color(hex6: 0x00FF88)

    // MARK: - Surfaces

    /// Primary app background (zinc-950).
    static let background = Color(hex6: 0x09090B)

    /// Card / raised surface (zinc-900).
    static let surface = Color(hex6: 0x18181B)

    /// Elevated surface — sits above `surface` (zinc-800).
    static let elevated = Color(hex6: 0x27272A)

    /// Editor / code / preview well. Kept at GitHub-dark `#0D1117` to match the
    /// `chat-ux-golden.html` code and chart wells exactly.
    static let codeBackground = Color(hex6: 0x0D1117)

    // MARK: - Lines

    /// Default hairline (zinc-800). Historical name, unchanged role.
    static let separator = Color(hex6: 0x27272A)

    /// Meaningful border — the one used on interactive containers. Chosen over
    /// `separator` wherever a border communicates an edge the user can act on,
    /// because `separator` alone does not clear WCAG 1.4.11 against `surface`.
    static let borderStrong = Color(hex6: 0x3F3F46)

    // MARK: - Text

    /// Body / primary text (zinc-50).
    static let primaryText = Color(hex6: 0xFAFAFA)

    /// Subdued secondary text (zinc-400).
    static let secondaryText = Color(hex6: 0xA1A1AA)

    /// Tertiary / metadata text (zinc-500). Never used for essential copy.
    static let faintText = Color(hex6: 0x71717A)

    // MARK: - Status

    /// Warning / in-flight amber.
    static let warning = Color(hex6: 0xF59E0B)

    /// Failure red.
    static let danger = Color(hex6: 0xEF4444)

    // MARK: - Metrics

    /// Maximum readable column for a chat transcript, matching the ThoxMythos
    /// web `max-w-3xl` and the `thoxos-ios` `Size.chatMaxWidth`.
    static let chatMaxWidth: CGFloat = 768

    /// Minimum interactive target. 44pt is the Apple HIG floor.
    static let hitTarget: CGFloat = 44

    /// Container corner radius (`Radius.xl`).
    static let containerRadius: CGFloat = 16

    /// Control corner radius (`Radius.lg`).
    static let controlRadius: CGFloat = 12
}

extension Color {
    /// Builds an opaque color from a packed `0xRRGGBB` literal in sRGB.
    ///
    /// Using a single integer literal keeps the token table diffable against the
    /// upstream CSS custom properties without a per-channel arithmetic pass that
    /// is easy to typo.
    init(hex6 value: UInt32) {
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}

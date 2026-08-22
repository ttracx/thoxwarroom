// ThoxTheme.swift
// THOX brand tokens. Emerald green chip-mark accent (#05A451), dark-mode-first
// backgrounds, typography from system defaults. Single source of truth so
// chrome and loading overlays stay visually consistent across macOS + iOS.

import SwiftUI

enum ThoxTheme {
    /// THOX emerald green accent (brand standard).
    static let accent = Color(red: 5.0/255, green: 164.0/255, blue: 81.0/255)

    /// Primary app background (very dark neutral, matches OpenWebUI dark theme).
    static let background = Color(red: 12.0/255, green: 14.0/255, blue: 18.0/255)

    /// Secondary surface (cards, loading overlay backdrop).
    static let surface = Color(red: 22.0/255, green: 26.0/255, blue: 32.0/255)

    /// Subtle separator / chip border.
    static let separator = Color.white.opacity(0.08)

    /// Body / primary text.
    static let primaryText = Color.white

    /// Subdued secondary text (used in error states).
    static let secondaryText = Color(white: 0.65)
}

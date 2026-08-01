import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';

import 'theme_extensions.dart';

/// Resolved styling for a button variant.
typedef ButtonVariantStyle = ({
  Color background,
  Color foreground,
  AdaptiveButtonStyle adaptiveStyle,
});

/// Provides named button style presets derived from
/// [ThoxWarRoomThemeExtension] tokens.
class ThoxWarRoomButtonStyles {
  /// Creates button styles from the given [theme] extension.
  const ThoxWarRoomButtonStyles(this.theme);

  /// The theme extension supplying color tokens.
  final ThoxWarRoomThemeExtension theme;

  /// Filled button with the theme primary color.
  ButtonVariantStyle primary() => (
    background: theme.buttonPrimary,
    foreground: theme.buttonPrimaryText,
    adaptiveStyle: AdaptiveButtonStyle.filled,
  );

  /// Bordered button with secondary colors.
  ButtonVariantStyle secondary() => (
    background: theme.buttonSecondary,
    foreground: theme.buttonSecondaryText,
    adaptiveStyle: AdaptiveButtonStyle.bordered,
  );

  /// Filled button with the error/destructive color.
  ButtonVariantStyle destructive() => (
    background: theme.error,
    foreground: theme.buttonPrimaryText,
    adaptiveStyle: AdaptiveButtonStyle.filled,
  );

  /// Transparent button for subtle actions.
  ButtonVariantStyle ghost() => (
    background: Colors.transparent,
    foreground: theme.textSecondary,
    adaptiveStyle: AdaptiveButtonStyle.plain,
  );
}

/// Convenient access to [ThoxWarRoomButtonStyles] from a
/// [BuildContext].
extension ThoxWarRoomButtonStylesContext on BuildContext {
  /// Returns [ThoxWarRoomButtonStyles] resolved from the current
  /// theme.
  ThoxWarRoomButtonStyles get thoxButtonStyles =>
      ThoxWarRoomButtonStyles(thoxTheme);
}

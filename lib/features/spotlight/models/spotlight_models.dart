import 'package:flutter/foundation.dart';

/// Configuration for the Spotlight floating chat bar.
@immutable
class SpotlightConfig {
  const SpotlightConfig({
    this.enabled = true,
    this.shortcut = 'Shift+Cmd+I',
    this.autoFocus = true,
    this.sendOnEnter = true,
    this.clearAfterSend = true,
  });

  final bool enabled;
  final String shortcut;
  final bool autoFocus;
  final bool sendOnEnter;
  final bool clearAfterSend;

  SpotlightConfig copyWith({
    bool? enabled,
    String? shortcut,
    bool? autoFocus,
    bool? sendOnEnter,
    bool? clearAfterSend,
  }) {
    return SpotlightConfig(
      enabled: enabled ?? this.enabled,
      shortcut: shortcut ?? this.shortcut,
      autoFocus: autoFocus ?? this.autoFocus,
      sendOnEnter: sendOnEnter ?? this.sendOnEnter,
      clearAfterSend: clearAfterSend ?? this.clearAfterSend,
    );
  }

  /// Default shortcut for the current platform.
  static String defaultShortcut() {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return 'Shift+Cmd+I';
    }
    return 'Shift+Ctrl+I';
  }
}

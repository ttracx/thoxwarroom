import 'dart:async';

import 'package:thoxwarroom/core/services/haptic_service.dart';

/// Platform-specific utilities for enhanced user experience.
///
/// Provides convenience methods for triggering haptic feedback
/// on supported platforms (iOS and Android).
class PlatformUtils {
  PlatformUtils._();

  /// Whether the current device supports haptic feedback.
  static bool get supportsHaptics => ThoxWarRoomHaptics.supportsHaptics;

  /// Trigger light haptic feedback.
  static void lightHaptic() {
    if (supportsHaptics) {
      unawaited(ThoxWarRoomHaptics.lightImpact());
    }
  }

  /// Trigger medium haptic feedback.
  static void mediumHaptic() {
    if (supportsHaptics) {
      unawaited(ThoxWarRoomHaptics.mediumImpact());
    }
  }

  /// Trigger heavy haptic feedback.
  static void heavyHaptic() {
    if (supportsHaptics) {
      unawaited(ThoxWarRoomHaptics.heavyImpact());
    }
  }

  /// Trigger selection haptic feedback.
  static void selectionHaptic() {
    if (supportsHaptics) {
      unawaited(ThoxWarRoomHaptics.selectionClick());
    }
  }
}

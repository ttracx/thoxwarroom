import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/debug_logger.dart';

/// Service that manages the Spotlight floating overlay window on desktop platforms.
/// On mobile platforms (iOS/Android), all methods are no-ops.
class SpotlightWindowService {
  static const _channel = MethodChannel('ai.thox.warroom/spotlight');

  bool _isDesktop = false;

  SpotlightWindowService() {
    _isDesktop = !kIsWeb && (Platform.isMacOS || Platform.isWindows);
  }

  /// Show the Spotlight floating window.
  Future<void> showSpotlight() async {
    if (!_isDesktop) return;
    try {
      await _channel.invokeMethod('showSpotlight');
      DebugLogger.log('Spotlight shown', scope: 'spotlight/show');
    } on PlatformException catch (e) {
      DebugLogger.log('Failed to show spotlight: ${e.message}', scope: 'spotlight/show');
    }
  }

  /// Hide the Spotlight floating window.
  Future<void> hideSpotlight() async {
    if (!_isDesktop) return;
    try {
      await _channel.invokeMethod('hideSpotlight');
      DebugLogger.log('Spotlight hidden', scope: 'spotlight/hide');
    } on PlatformException catch (e) {
      DebugLogger.log('Failed to hide spotlight: ${e.message}', scope: 'spotlight/hide');
    }
  }

  /// Toggle the Spotlight floating window.
  Future<void> toggleSpotlight() async {
    if (!_isDesktop) return;
    try {
      await _channel.invokeMethod('toggleSpotlight');
    } on PlatformException catch (e) {
      DebugLogger.log('Failed to toggle spotlight: ${e.message}', scope: 'spotlight/toggle');
    }
  }

  /// Check if the Spotlight window is currently visible.
  Future<bool> isSpotlightVisible() async {
    if (!_isDesktop) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isSpotlightVisible');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Whether the spotlight is supported on this platform.
  bool get isSupported => _isDesktop;
}

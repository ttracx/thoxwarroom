import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

/// Whether ThoxWarRoom can rely on native iOS Liquid Glass rendering.
bool thoxSupportsNativeGlass({bool? isIOS, int? iosMajorVersion}) {
  final effectiveIsIOS = isIOS ?? PlatformInfo.isIOS;
  if (!effectiveIsIOS) {
    return false;
  }

  final effectiveIosVersion = iosMajorVersion ?? PlatformInfo.iOSVersion;
  return effectiveIosVersion >= 26;
}

/// Whether glass-styled chrome should use ThoxWarRoom's opaque fallback treatment.
bool thoxUsesOpaqueGlassFallback({
  bool? isAndroid,
  bool? isIOS,
  int? iosMajorVersion,
}) {
  if (isAndroid ?? PlatformInfo.isAndroid) {
    return true;
  }

  final effectiveIsIOS = isIOS ?? PlatformInfo.isIOS;
  return effectiveIsIOS &&
      !thoxSupportsNativeGlass(
        isIOS: effectiveIsIOS,
        iosMajorVersion: iosMajorVersion,
      );
}

import 'package:flutter_test/flutter_test.dart';

import 'package:thoxwarroom/shared/utils/adaptive_glass.dart';

void main() {
  group('thoxSupportsNativeGlass', () {
    test('requires iOS 26 or newer', () {
      expect(
        thoxSupportsNativeGlass(isIOS: true, iosMajorVersion: 26),
        true,
      );
      expect(
        thoxSupportsNativeGlass(isIOS: true, iosMajorVersion: 27),
        true,
      );
      expect(
        thoxSupportsNativeGlass(isIOS: true, iosMajorVersion: 25),
        false,
      );
      expect(
        thoxSupportsNativeGlass(isIOS: true, iosMajorVersion: 0),
        false,
      );
    });

    test('is false outside iOS', () {
      expect(
        thoxSupportsNativeGlass(isIOS: false, iosMajorVersion: 26),
        false,
      );
    });
  });

  group('thoxUsesOpaqueGlassFallback', () {
    test('uses fallback on Android and older iOS', () {
      expect(thoxUsesOpaqueGlassFallback(isAndroid: true), true);
      expect(
        thoxUsesOpaqueGlassFallback(
          isAndroid: false,
          isIOS: true,
          iosMajorVersion: 18,
        ),
        true,
      );
    });

    test('does not use fallback on iOS 26 or non-mobile platforms', () {
      expect(
        thoxUsesOpaqueGlassFallback(
          isAndroid: false,
          isIOS: true,
          iosMajorVersion: 26,
        ),
        false,
      );
      expect(
        thoxUsesOpaqueGlassFallback(isAndroid: false, isIOS: false),
        false,
      );
    });
  });
}

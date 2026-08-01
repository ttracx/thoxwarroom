import 'package:flutter/foundation.dart';

const appleAppStoreReviewUrl =
    'https://apps.apple.com/us/app/thoxwarroom-client/id6749840287?action=write-review';
const googlePlayStoreUrl =
    'https://play.google.com/store/apps/details?id=ai.thox.warroom';

String reviewUrlForPlatform([TargetPlatform? platform]) {
  final resolved = platform ?? defaultTargetPlatform;
  return switch (resolved) {
    TargetPlatform.iOS || TargetPlatform.macOS => appleAppStoreReviewUrl,
    _ => googlePlayStoreUrl,
  };
}

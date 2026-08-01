import 'dart:io';

import 'package:checks/checks.dart';
import 'package:thoxwarroom/core/network/thoxwarroom_user_agent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThoxWarRoomUserAgent', () {
    test('builds a product and app-version token', () {
      check(
        ThoxWarRoomUserAgent.build(appVersion: ' 3.4.3 '),
      ).equals('ThoxWarRoom/3.4.3');
    });

    test('sanitizes characters that are invalid in a product token', () {
      check(
        ThoxWarRoomUserAgent.build(appVersion: '3.4 beta/1'),
      ).equals('ThoxWarRoom/3.4-beta-1');
    });

    test('falls back to the product name when the version is empty', () {
      check(ThoxWarRoomUserAgent.build(appVersion: '   ')).equals('ThoxWarRoom');
    });

    test('configure updates the process-wide identity', () {
      addTearDown(() => ThoxWarRoomUserAgent.configure(appVersion: ''));

      ThoxWarRoomUserAgent.configure(appVersion: '9.8.7');

      check(ThoxWarRoomUserAgent.value).equals('ThoxWarRoom/9.8.7');
    });

    test('runtime fallback matches dart:io', () {
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      check(ThoxWarRoomUserAgent.runtimeDefaultValue).equals(client.userAgent);
    });

    test('replaces case variants with one canonical header', () {
      final original = <String, String>{
        'user-agent': 'spoofed',
        'X-Custom': 'value',
      };

      final merged = ThoxWarRoomUserAgent.mergeHeaders(original);

      check(merged[ThoxWarRoomUserAgent.headerName]).equals(ThoxWarRoomUserAgent.value);
      check(
        merged.keys.where(ThoxWarRoomUserAgent.isHeaderName),
      ).deepEquals([ThoxWarRoomUserAgent.headerName]);
      check(merged['X-Custom']).equals('value');
      check(original['user-agent']).equals('spoofed');
    });
  });
}

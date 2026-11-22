import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:idris/features/settings/about_page.dart';

/// The version shown in About and crash logs must be the one in pubspec.yaml.
void main() {
  test('About shows the pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([0-9.]+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull);
    expect(kAppVersion, match!.group(1));
  });
}

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idris/core/layout.dart';

void main() {
  test('a phone upright is mobile; on its side, the tablet frame', () {
    expect(VLayout.forSize(const Size(412, 915)), VLayout.mobile);
    expect(VLayout.forSize(const Size(915, 412)), VLayout.tablet);
  });

  test('a small window stays mobile, either way round', () {
    expect(VLayout.forSize(const Size(600, 400)), VLayout.mobile);
    expect(VLayout.forSize(const Size(400, 600)), VLayout.mobile);
  });

  test('tablets and desktop windows', () {
    expect(VLayout.forSize(const Size(800, 1200)), VLayout.tablet);
    expect(VLayout.forSize(const Size(1280, 800)), VLayout.desktop);
    // Wide but short: not room for the sidebar's columns.
    expect(VLayout.forSize(const Size(1400, 500)), VLayout.tablet);
  });
}

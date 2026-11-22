import 'package:flutter_test/flutter_test.dart';
import 'package:idris/platform/volume_keys.dart';

void main() {
  late DateTime now;
  late List<int> steps;
  late List<int> skips;
  late VolumeKeys keys;

  setUp(() {
    now = DateTime(2026, 11, 22);
    steps = [];
    skips = [];
    keys = VolumeKeys(onStep: steps.add, onHold: skips.add, now: () => now);
  });

  /// Presses [direction] at each of [ms] (milliseconds from the start).
  void pressAt(int direction, List<int> ms) {
    final start = now;
    for (final t in ms) {
      now = start.add(Duration(milliseconds: t));
      keys.press(direction);
    }
  }

  /// A key held for [heldMs]: down at 0, then Android's repeats every
  /// 50 ms from 500 ms.
  List<int> held(int heldMs) => [0, for (var t = 500; t <= heldMs; t += 50) t];

  int volume() => steps.fold(0, (a, b) => a + b);

  test('a tap changes the volume at once', () {
    pressAt(1, [0]);
    expect(steps, [1]);
    expect(skips, isEmpty);
  });

  test('taps a moment apart each change the volume', () {
    pressAt(-1, [0, 400, 800, 1250]);
    expect(volume(), -4);
    expect(skips, isEmpty);
  });

  test('a double tap skips, and leaves the volume as it was', () {
    pressAt(1, [0, 180]);
    expect(skips, [1]);
    expect(volume(), 0);
  });

  test('a double tap on Volume down goes to the previous track', () {
    pressAt(-1, [0, 250]);
    expect(skips, [-1]);
    expect(volume(), 0);
  });

  test('a third quick tap after a double tap is a volume step', () {
    pressAt(1, [0, 180, 400]);
    expect(skips, [1]);
    expect(volume(), 1);
  });

  test('holding Volume up skips once, and leaves the volume as it was', () {
    pressAt(1, held(2000));
    expect(skips, [1]);
    expect(volume(), 0);
  });

  test('holding Volume down goes to the previous track', () {
    pressAt(-1, held(900));
    expect(skips, [-1]);
    expect(volume(), 0);
  });

  test('after a hold, a tap changes the volume again', () {
    pressAt(1, held(800));
    pressAt(1, [1100]);
    expect(skips, [1]);
    expect(volume(), 1);
  });

  test('holding again later skips again', () {
    pressAt(1, held(800));
    now = now.add(const Duration(seconds: 3));
    pressAt(1, held(800));
    expect(skips, [1, 1]);
    expect(volume(), 0);
  });

  test('a release on its own does nothing', () {
    keys.press(0);
    expect(steps, isEmpty);
    expect(skips, isEmpty);
  });

  /// With the screen off: the key goes down, nothing repeats, and the
  /// release comes as a press of 0 at [upMs].
  void downUp(int direction, int downMs, int upMs) {
    final start = now;
    now = start.add(Duration(milliseconds: downMs));
    keys.press(direction);
    now = start.add(Duration(milliseconds: upMs));
    keys.press(0);
    now = start;
  }

  test('screen off: a key held, then let go, skips', () {
    downUp(1, 0, 2000);
    expect(skips, [1]);
    expect(volume(), 0);
  });

  test('screen off: a tap (down and up) changes the volume', () {
    downUp(-1, 0, 150);
    expect(skips, isEmpty);
    expect(volume(), -1);
  });

  test('screen off: a double tap skips, its releases change nothing', () {
    downUp(1, 0, 120);
    downUp(1, 200, 330);
    expect(skips, [1]);
    expect(volume(), 0);
  });

  test('screen on: the release after a repeating hold skips no more', () {
    pressAt(1, held(1200));
    now = now.add(const Duration(milliseconds: 40));
    keys.press(0);
    expect(skips, [1]);
    expect(volume(), 0);
  });
}

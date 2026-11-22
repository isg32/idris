import 'package:flutter/services.dart';

/// Tells a tap on a volume key from a skip gesture: a tap changes the
/// volume (at once, so it never feels slow); a double tap or a hold skips,
/// Volume up to the next track and Volume down to the previous.
///
/// A double tap is two presses less than [doubleTapGap] apart. A hold is
/// seen two ways. With the screen on, Android repeats a held key about
/// every 50 ms, faster than anyone taps (closer than [repeatGap]). With the
/// screen off it doesn't repeat, but it does pass on the key's release (as
/// a press of 0), so a key let go after [holdTime] or more was held.
/// Either way, the volume steps the gesture took first are undone, and it
/// skips once.
class VolumeKeys {
  VolumeKeys({
    required this.onStep,
    required this.onHold,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Changes the volume one step: +1 up, -1 down.
  final void Function(int direction) onStep;

  /// Skips (a double tap or a hold): +1 to the next track, -1 to the
  /// previous.
  final void Function(int direction) onHold;

  final DateTime Function() _now;

  /// Closer than this, a press is the key repeating (held).
  static const repeatGap = Duration(milliseconds: 150);

  /// Two presses closer than this (but not repeats) are a double tap.
  static const doubleTapGap = Duration(milliseconds: 300);

  /// A key let go this long after it went down was held.
  static const holdTime = Duration(milliseconds: 500);

  /// When the key now down went down, until it's let go.
  DateTime? _downAt;

  /// Further apart than this, presses belong to separate taps.
  static const burstGap = Duration(milliseconds: 700);

  int _direction = 0;
  DateTime? _last;
  bool _holding = false;

  /// Volume steps taken in this burst of presses (undone if it's a hold).
  int _steps = 0;

  /// A press of a volume key: +1 up, -1 down.
  void press(int direction) {
    final now = _now();
    if (direction == 0) {
      _release(now);
      return;
    }
    // A repeat keeps the key's first press as when it went down.
    _downAt ??= now;
    final last = _last;
    _last = now;
    final gap = last == null ? null : now.difference(last);
    if (direction != _direction || gap == null || gap > burstGap) {
      // A new press.
      _direction = direction;
      _holding = false;
      _steps = 1;
      _downAt = now;
      onStep(direction);
      return;
    }
    if (gap < repeatGap) {
      if (_holding) return; // still held: it skipped already
      _holding = true;
      for (var i = 0; i < _steps; i++) {
        onStep(-direction);
      }
      _steps = 0;
      onHold(direction);
      return;
    }
    if (!_holding && _steps == 1 && gap <= doubleTapGap) {
      // A double tap: like a hold.
      _holding = true;
      onStep(-direction);
      _steps = 0;
      onHold(direction);
      return;
    }
    // Another tap soon after the last (or the key let go after a skip).
    _holding = false;
    _steps++;
    onStep(direction);
  }

  /// The key was let go (Android's press of 0): after [holdTime], a hold
  /// (the only way to see one with the screen off).
  void _release(DateTime now) {
    final down = _downAt;
    _downAt = null;
    if (down == null || _holding || _direction == 0) return;
    if (now.difference(down) < holdTime) return;
    _holding = true;
    for (var i = 0; i < _steps; i++) {
      onStep(-_direction);
    }
    _steps = 0;
    onHold(_direction);
  }
}

/// Changes the phone's media volume one step, showing Android's volume
/// panel (see MainActivity.kt).
Future<void> stepMediaVolume(int direction) =>
    const MethodChannel('idris/volume')
        .invokeMethod<void>('step', {'direction': direction});

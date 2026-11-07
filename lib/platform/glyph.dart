import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nothing_glyph_interface/nothing_glyph_interface.dart';

/// A slow breathing pulse on the Nothing Phone (2a) Glyph strip while audio
/// plays (Settings → Glyph, off by default).
///
/// The strip C1–C24 (channels 0–23) fills over 4 s and empties over 6 s,
/// Veronica's breathing rhythm. Nothing lets only an app in the foreground
/// light the Glyphs, so the pulse pauses while Idris is in the background.
/// Like Veronica, it needs Glyph debug mode on (one adb command).
class GlyphBreath {
  GlyphBreath._();

  static final GlyphBreath instance = GlyphBreath._();

  static const _frame = Duration(milliseconds: 125);
  static const _in = 4.0, _out = 6.0;

  final NothingGlyphInterface _glyph = NothingGlyphInterface();
  Future<bool>? _ready;
  Timer? _timer;
  int _lastLit = -1;

  /// True on a Phone (2a) whose Glyph service connected.
  Future<bool> get available => _ready ??= _connect();

  Future<bool> _connect() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      if (await _glyph.is23111() != true && await _glyph.is23113() != true) {
        return false;
      }
      await _glyph.init();
      return true;
    } on Object {
      return false;
    }
  }

  bool get running => _timer != null;

  /// How many of the 24 segments are lit [t] seconds into the breath.
  static int litAt(double t) {
    final c = t % (_in + _out);
    final level = c < _in ? c / _in : 1 - (c - _in) / _out;
    return (level * 24).round().clamp(0, 24);
  }

  Future<void> start() async {
    if (running || !await available) return;
    final begin = DateTime.now();
    _timer = Timer.periodic(_frame, (_) {
      final t = DateTime.now().difference(begin).inMilliseconds / 1000;
      unawaited(_show(litAt(t)));
    });
  }

  Future<void> _show(int lit) async {
    if (lit == _lastLit) return;
    _lastLit = lit;
    try {
      if (lit == 0) {
        await _glyph.turnOff();
        return;
      }
      var builder = GlyphFrameBuilder();
      for (var i = 0; i < lit; i++) {
        builder = builder.buildChannel(i);
      }
      await _glyph.buildGlyphFrame(builder.build());
      await _glyph.toggle();
    } on Object {
      // A missed frame is fine; the next one redraws.
    }
  }

  void stop() {
    if (_timer == null) return;
    _timer?.cancel();
    _timer = null;
    _lastLit = -1;
    unawaited(_glyph.turnOff().catchError((Object _) {}));
  }
}

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:idris/data/models.dart';
import 'package:idris/platform/cache_manager.dart';
import 'package:idris/platform/glyph.dart';
import 'package:idris/platform/playback_rules.dart';
import 'package:idris/platform/quality.dart';

void main() {
  group('pickAudio', () {
    // What YouTube usually offers.
    const streams = [
      AudioCandidate(kbps: 48, m4a: false, value: 'webm-48'),
      AudioCandidate(kbps: 66, m4a: false, value: 'webm-66'),
      AudioCandidate(kbps: 127, m4a: true, value: 'm4a-128'),
      AudioCandidate(kbps: 156, m4a: false, value: 'webm-160'),
    ];

    test('best is the highest bitrate', () {
      expect(pickAudio(streams, AudioQuality.best), 'webm-160');
    });
    test('low is the lowest bitrate', () {
      expect(pickAudio(streams, AudioQuality.low), 'webm-48');
    });
    test('high and medium are the closest to 160 and 128', () {
      expect(pickAudio(streams, AudioQuality.high), 'webm-160');
      expect(pickAudio(streams, AudioQuality.medium), 'm4a-128');
    });
    test('m4a wins a tie', () {
      const tie = [
        AudioCandidate(kbps: 128, m4a: false, value: 'webm'),
        AudioCandidate(kbps: 128, m4a: true, value: 'm4a'),
      ];
      for (final q in AudioQuality.values) {
        expect(pickAudio(tie, q), 'm4a', reason: q.name);
      }
    });
    test('nothing on offer is null', () {
      expect(pickAudio(<AudioCandidate<String>>[], AudioQuality.best), isNull);
    });
    test('parse falls back to best', () {
      expect(AudioQuality.parse('low'), AudioQuality.low);
      expect(AudioQuality.parse(null), AudioQuality.best);
      expect(AudioQuality.parse('nonsense'), AudioQuality.best);
    });
  });

  group('diffPlaylist', () {
    test('finds added and removed videos', () {
      final d = diffPlaylist(['a', 'b', 'c'], ['b', 'c', 'd', 'e']);
      expect(d.added, ['d', 'e']);
      expect(d.removed, ['a']);
    });
    test('a reorder is no change', () {
      final d = diffPlaylist(['a', 'b'], ['b', 'a']);
      expect(d.added, isEmpty);
      expect(d.removed, isEmpty);
    });
  });

  group('chooseEvictions', () {
    final t0 = DateTime(2026, 11, 1);
    CacheEntry e(String id, int mb, {int? playedDay, int cachedDay = 0}) =>
        CacheEntry(
          videoId: id,
          path: '/$id',
          bytes: mb * 1024 * 1024,
          kbps: 160,
          mime: 'audio/mp4',
          complete: true,
          lastPlayedAt: playedDay == null
              ? null
              : t0.add(Duration(days: playedDay)),
          cachedAt: t0.add(Duration(days: cachedDay)),
        );
    const mb = 1024 * 1024;

    test('nothing goes while under the limit', () {
      expect(
        chooseEvictions(
          [e('a', 10), e('b', 10)],
          pinned: {},
          keep: {},
          limitBytes: 20 * mb,
        ),
        isEmpty,
      );
    });

    test('least recently played goes first, pinned never', () {
      final out = chooseEvictions(
        [
          e('old', 10, playedDay: 1),
          e('new', 10, playedDay: 5),
          e('pinned', 100, playedDay: 0),
          e('mid', 10, playedDay: 3),
        ],
        pinned: {'pinned'},
        keep: {},
        limitBytes: 15 * mb,
      );
      expect(out.map((x) => x.videoId), ['old', 'mid']);
    });

    test('never played counts from when it was cached', () {
      final out = chooseEvictions(
        [e('played', 10, playedDay: 4), e('fetched', 10, cachedDay: 2)],
        pinned: {},
        keep: {},
        limitBytes: 10 * mb,
      );
      expect(out.map((x) => x.videoId), ['fetched']);
    });

    test('the track playing is kept even if oldest', () {
      final out = chooseEvictions(
        [e('playing', 10, playedDay: 0), e('other', 10, playedDay: 1)],
        pinned: {},
        keep: {'playing'},
        limitBytes: 10 * mb,
      );
      expect(out.map((x) => x.videoId), ['other']);
    });
  });

  group('afterTrackEnds', () {
    AfterTrack run({
      bool sleepAtEnd = false,
      Loop loop = Loop.off,
      int? target,
      int done = 1,
      RepeatEnd end = RepeatEnd.next,
      bool hasNext = true,
    }) => afterTrackEnds(
      sleepAtEnd: sleepAtEnd,
      loop: loop,
      repeatTarget: target,
      repeatDone: done,
      repeatEnd: end,
      hasNext: hasNext,
    );

    test('plain play moves on, and stops at the end', () {
      expect(run(), AfterTrack.next);
      expect(run(hasNext: false), AfterTrack.stop);
    });
    test('loop one replays forever', () {
      expect(run(loop: Loop.one, hasNext: false), AfterTrack.replay);
    });
    test('loop all goes back to the first track after the last', () {
      expect(run(loop: Loop.all), AfterTrack.next);
      expect(run(loop: Loop.all, hasNext: false), AfterTrack.wrap);
    });
    test('a finished repeat count on the last track wraps when looping', () {
      expect(
        run(target: 3, done: 3, loop: Loop.all, hasNext: false),
        AfterTrack.wrap,
      );
    });
    test('the loop button cycles off, all, one', () {
      expect(Loop.off.next, Loop.all);
      expect(Loop.all.next, Loop.one);
      expect(Loop.one.next, Loop.off);
    });
    test('a repeat count of 3 plays three times, then moves on', () {
      expect(run(target: 3, done: 1), AfterTrack.replay);
      expect(run(target: 3, done: 2), AfterTrack.replay);
      expect(run(target: 3, done: 3), AfterTrack.next);
    });
    test('a repeat count can stop instead', () {
      expect(run(target: 3, done: 3, end: RepeatEnd.stop), AfterTrack.stop);
    });
    test('sleep at end of track beats everything', () {
      expect(
        run(sleepAtEnd: true, loop: Loop.one, target: 108),
        AfterTrack.stop,
      );
    });
  });

  test('shuffledFrom keeps the current track first and loses nothing', () {
    final q = List.generate(20, (i) => i);
    final s = shuffledFrom(q, 7, random: math.Random(1));
    expect(s.first, 7);
    expect(s.toSet(), q.toSet());
    expect(s.length, q.length);
  });

  test('glyph breath fills in 4 s and empties over 6 s', () {
    expect(GlyphBreath.litAt(0), 0);
    expect(GlyphBreath.litAt(2), 12);
    expect(GlyphBreath.litAt(4), 24);
    expect(GlyphBreath.litAt(7), 12);
    expect(GlyphBreath.litAt(10), 0);
  });

  test('settings read from prefs, with defaults', () {
    final d = Settings.fromPrefs({});
    expect(d.quality, AudioQuality.best);
    expect(d.cacheLimitGb, 5);
    expect(d.precacheWifiOnly, isTrue);
    expect(d.glyph, isFalse);
    final s = Settings.fromPrefs({
      'quality': 'medium',
      'cacheLimitGb': '0',
      'precacheWifiOnly': 'false',
    });
    expect(s.quality, AudioQuality.medium);
    expect(s.cacheLimitBytes, isNull);
    expect(s.precacheWifiOnly, isFalse);
  });
}

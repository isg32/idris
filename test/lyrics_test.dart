import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:idris/data/models.dart';
import 'package:idris/platform/lyrics.dart';

Track track(String id, String title, String channel, {int ms = 180000}) =>
    Track(
      videoId: id,
      title: title,
      channel: channel,
      durationMs: ms,
      pinned: false,
    );

void main() {
  group('LRC', () {
    test('timed lines, in order, with repeated lines and an offset', () {
      final l = parseLrc('''
[ar:The Marías]
[offset:500]
[00:12.50]Ay, no puedo
[00:20.00][00:40.00]Chorus line
[00:30.1]
''', source: 'LRCLIB');
      expect(l.synced, isTrue);
      expect(l.lines.map((x) => x.text), [
        'Ay, no puedo',
        'Chorus line',
        '',
        'Chorus line',
      ]);
      // +500 ms offset shows lines half a second sooner.
      expect(l.lines.first.at, const Duration(milliseconds: 12000));
      expect(l.lineAt(const Duration(seconds: 25)), 1);
      expect(l.lineAt(const Duration(seconds: 5)), -1);
    });

    test('without times, plain lyrics', () {
      final l = parseLrc('\nOm namah shivaya\n\nOm\n', source: 'LRCLIB');
      expect(l.synced, isFalse);
      expect(l.lines.map((x) => x.text), ['Om namah shivaya', '', 'Om']);
      expect(l.lineAt(const Duration(seconds: 3)), -1);
    });
  });

  group('a video as a song', () {
    test('Artist - Title (Official Video)', () {
      expect(
        songOf('PinkPantheress - Mosquito (Official Video)', 'PinkPantheress'),
        (artist: 'PinkPantheress', title: 'Mosquito'),
      );
    });

    test('featured artists and lyric-video tags go', () {
      expect(
        songOf(
          'SAILORR - POOKIE\'S REQUIEM (feat. Summer Walker) [Lyric Video]',
          'SAILORR',
        ),
        (artist: 'SAILORR', title: 'POOKIE\'S REQUIEM'),
      );
    });

    test('no dash: the channel, without "- Topic", is the artist', () {
      expect(songOf('Crush', 'Solange - Topic'), (
        artist: 'Solange',
        title: 'Crush',
      ));
    });

    test('an album after a bar is dropped', () {
      expect(songOf('Clairo - Flamin Hot Cheetos | diary 001', 'Clairo'), (
        artist: 'Clairo',
        title: 'Flamin Hot Cheetos',
      ));
    });
  });

  group('picking from LRCLIB', () {
    Map<String, Object?> r({
      double? duration,
      String? synced,
      String? plain,
      bool instrumental = false,
    }) => {
      'duration': duration,
      'syncedLyrics': synced,
      'plainLyrics': plain,
      'instrumental': instrumental,
    };

    test('synced and closest in length', () {
      expect(
        pickLyrics([
          r(duration: 300, synced: '[00:01.00]far'),
          r(duration: 182, synced: '[00:01.00]near'),
          r(duration: 180, plain: 'plain'),
        ], const Duration(seconds: 180)),
        '[00:01.00]near',
      );
    });

    test('a synced version of another length gives way to plain', () {
      expect(
        pickLyrics([
          r(duration: 1200, synced: '[00:01.00]live set'),
          r(duration: 181, plain: 'studio words'),
        ], const Duration(seconds: 180)),
        'studio words',
      );
    });

    test('with a strict length, only a match that close', () {
      expect(
        pickLyrics(
          [
            r(duration: 190, synced: '[00:01.00]another song'),
            r(duration: 181.5, synced: '[00:01.00]this one'),
          ],
          const Duration(seconds: 180),
          within: 3,
        ),
        '[00:01.00]this one',
      );
      expect(
        pickLyrics(
          [r(duration: 190, synced: '[00:01.00]x')],
          const Duration(seconds: 180),
          within: 3,
        ),
        isNull,
      );
    });

    test('instrumentals and empties give nothing', () {
      expect(
        pickLyrics([
          r(duration: 180, instrumental: true, synced: '[00:01.00]x'),
          r(duration: 180, plain: '  '),
        ], const Duration(seconds: 180)),
        isNull,
      );
    });
  });

  group('the service', () {
    late Directory tmp;
    late int hits;
    late List<Object?> answer;
    var now = DateTime(2026, 11, 23);

    LyricsService service({Future<String?> Function(String)? local}) =>
        LyricsService(
          dir: () async => Directory('${tmp.path}/lyrics'),
          client: MockClient((req) async {
            hits++;
            expect(req.url.host, 'lrclib.net');
            return http.Response(jsonEncode(answer), 200);
          }),
          localUri: local,
          now: () => now,
        );

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('idris_lyrics_');
      hits = 0;
      answer = [];
      now = DateTime(2026, 11, 23);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('found once, then kept: no second look-up', () async {
      answer = [
        {'duration': 180, 'syncedLyrics': '[00:01.00]Hello'},
      ];
      final t = track('abc', 'Adele - Hello (Official Video)', 'AdeleVEVO');
      expect((await service().lyricsFor(t))!.lines.single.text, 'Hello');
      expect((await service().lyricsFor(t))!.lines.single.text, 'Hello');
      expect(hits, 1, reason: 'the second came from the kept file');
    });

    test('none found: not asked again for a week', () async {
      final t = track('xyz', 'Untitled chant', 'Some channel');
      expect(await service().lyricsFor(t), isNull);
      final first = hits; // the search, and the retry by title alone
      expect(await service().lyricsFor(t), isNull);
      expect(hits, first);
      now = now.add(const Duration(days: 8));
      // The marker's age is its file time: make it a week old.
      final marker = File('${tmp.path}/lyrics/xyz.none');
      marker.setLastModifiedSync(
        DateTime.now().subtract(const Duration(days: 8)),
      );
      now = DateTime.now();
      await service().lyricsFor(t);
      expect(hits, greaterThan(first));
    });

    test('an .lrc beside a local file, without going online', () async {
      final song = File('${tmp.path}/Music/Om.mp3')
        ..createSync(recursive: true);
      File('${tmp.path}/Music/Om.lrc').writeAsStringSync('[00:02.00]Om');
      final l = await service(local: (_) async => song.path)
          .lyricsFor(track('local:1', 'Om', ''));
      expect(l!.source, 'file');
      expect(l.lines.single.text, 'Om');
      expect(hits, 0);
    });
  });
}

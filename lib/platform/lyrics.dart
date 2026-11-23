import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../data/models.dart';
import 'local_music.dart';

/// A line of lyrics, and when it's sung (null in lyrics without times).
class LyricLine {
  const LyricLine(this.text, [this.at]);
  final String text;
  final Duration? at;
}

/// A song's lyrics: synced (each line timed, to follow along) or plain.
class Lyrics {
  const Lyrics(this.lines, {required this.source});

  final List<LyricLine> lines;

  /// Where they came from: `LRCLIB`, or `file` (an .lrc beside the music).
  final String source;

  bool get synced => lines.isNotEmpty && lines.first.at != null;

  /// The line being sung at [position] (-1 before the first).
  int lineAt(Duration position) {
    if (!synced) return -1;
    var i = -1;
    for (var j = 0; j < lines.length; j++) {
      if (lines[j].at! <= position) {
        i = j;
      } else {
        break;
      }
    }
    return i;
  }
}

/// Reads LRC: `[mm:ss.xx]` before each line (several tags for a repeated
/// line), `[offset:±ms]`, and metadata tags (`[ar:…]`), which are skipped.
/// Without any times, the lines are plain lyrics.
Lyrics parseLrc(String text, {required String source}) {
  final tag = RegExp(r'\[(\d+):(\d+(?:[.:]\d+)?)\]');
  var offset = Duration.zero;
  final timed = <LyricLine>[];
  final plain = <String>[];
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trimRight();
    final off = RegExp(r'^\[offset:\s*([+-]?\d+)\]').firstMatch(line);
    if (off != null) {
      // A positive offset shows lyrics sooner.
      offset = Duration(milliseconds: -int.parse(off[1]!));
      continue;
    }
    final times = tag.allMatches(line).toList();
    if (times.isEmpty) {
      if (RegExp(r'^\[[a-z]+:').hasMatch(line)) continue; // metadata
      plain.add(line.trim());
      continue;
    }
    final words = line.substring(times.last.end).trim();
    for (final t in times) {
      final seconds = double.parse(t[2]!.replaceAll(':', '.'));
      timed.add(
        LyricLine(
          words,
          Duration(
            milliseconds: int.parse(t[1]!) * 60000 + (seconds * 1000).round(),
          ),
        ),
      );
    }
  }
  if (timed.isEmpty) {
    // Plain lyrics: trim blank lines at the ends.
    while (plain.isNotEmpty && plain.first.isEmpty) {
      plain.removeAt(0);
    }
    while (plain.isNotEmpty && plain.last.isEmpty) {
      plain.removeLast();
    }
    return Lyrics([for (final l in plain) LyricLine(l)], source: source);
  }
  timed.sort((a, b) => a.at!.compareTo(b.at!));
  return Lyrics([
    for (final l in timed)
      LyricLine(
        l.text,
        l.at! + offset < Duration.zero ? Duration.zero : l.at! + offset,
      ),
  ], source: source);
}

/// A YouTube video's title and channel, as the song's artist and title:
/// "PinkPantheress - Mosquito (Official Video)" by "PinkPantheress" is
/// PinkPantheress, "Mosquito". Without "Artist - Title", the channel
/// (less " - Topic", "VEVO" and "Official") is the artist.
({String artist, String title}) songOf(String videoTitle, String channel) {
  var title = videoTitle;
  // (Official Video), [Lyric Video], (HD), (Audio), (Visualizer), (Live)…
  title = title.replaceAll(
    RegExp(
      r'[\(\[][^\)\]]*\b(official|video|audio|lyric|lyrics|visuali[sz]er|'
      r'hd|4k|hq|remaster(ed)?|music|mv|clip|live|full song|version)\b[^\)\]]*[\)\]]',
      caseSensitive: false,
    ),
    '',
  );
  // "| Album Name", "// …" after the song.
  title = title.split(RegExp(r'\s[|/]{1,2}\s')).first;
  var artist = '';
  final dash = RegExp(r'\s[-–—]\s').firstMatch(title);
  if (dash != null) {
    artist = title.substring(0, dash.start);
    title = title.substring(dash.end);
  } else {
    artist = channel
        .replaceAll(RegExp(r'\s*-\s*Topic$'), '')
        .replaceAll(RegExp(r'VEVO$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bofficial\b', caseSensitive: false), '');
  }
  // Featured artists don't help a search.
  String bare(String s) => s
      .replaceAll(
        RegExp(
          r'[\(\[]?\b(ft|feat|featuring)\.?\s[^\)\]]*[\)\]]?',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return (artist: bare(artist), title: bare(title));
}

/// Lyrics for the tracks Idris plays: an .lrc beside a local file, else
/// LRCLIB (lrclib.net: free and open, no account; only the title, artist
/// and length are sent). Found lyrics are kept in `<appSupport>/lyrics`,
/// so they're there offline and never looked up twice; a song with none
/// is noted too, and looked up again after [retryAfter].
class LyricsService {
  LyricsService({
    required this.dir,
    http.Client? client,
    this.localUri,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now;

  final Future<Directory> Function() dir;
  final http.Client _client;
  final DateTime Function() _now;

  /// Where a local track's file is (a path on Linux), for its .lrc.
  final Future<String?> Function(String videoId)? localUri;

  static const retryAfter = Duration(days: 7);

  final Map<String, Future<Lyrics?>> _finding = {};

  /// [track]'s lyrics, or null when there are none (yet).
  Future<Lyrics?> lyricsFor(Track track) =>
      _finding[track.videoId] ??= _find(track).whenComplete(() {
        // A block, not `=>`: whenComplete waits on a Future its callback
        // returns, and remove() returns this very one.
        _finding.remove(track.videoId);
      });

  Future<Lyrics?> _find(Track track) async {
    final d = await dir();
    final name = track.videoId.replaceAll(':', '_');
    final kept = File(p.join(d.path, '$name.lrc'));
    final none = File(p.join(d.path, '$name.none'));
    if (kept.existsSync()) {
      return parseLrc(await kept.readAsString(), source: 'LRCLIB');
    }
    // Beside a local file: Song.mp3 → Song.lrc.
    if (isLocal(track.videoId)) {
      final path = await localUri?.call(track.videoId);
      if (path != null && path.startsWith('/')) {
        final lrc = File('${p.withoutExtension(path)}.lrc');
        if (lrc.existsSync()) {
          return parseLrc(await lrc.readAsString(), source: 'file');
        }
      }
    }
    if (none.existsSync() &&
        _now().difference(none.lastModifiedSync()) < retryAfter) {
      return null;
    }
    final found = await _lrclib(track);
    await d.create(recursive: true);
    if (found == null) {
      await none.writeAsString('');
      return null;
    }
    await kept.writeAsString(found);
    if (none.existsSync()) await none.delete();
    return parseLrc(found, source: 'LRCLIB');
  }

  /// The best LRCLIB match's lyrics (synced if any match has them), as LRC.
  Future<String?> _lrclib(Track track) async {
    final song = isLocal(track.videoId)
        ? (artist: track.channel, title: track.title)
        : songOf(track.title, track.channel);
    if (song.title.isEmpty) return null;
    try {
      var results = await _search({
        'track_name': song.title,
        if (song.artist.isNotEmpty) 'artist_name': song.artist,
      });
      final length = Duration(milliseconds: track.durationMs);
      if (results.isEmpty) {
        // The artist may be wrong (a channel's name): both as free text.
        results = await _search({'q': '${song.artist} ${song.title}'.trim()});
      }
      final found = pickLyrics(results, length);
      if (found != null || length == Duration.zero) return found;
      // Last, the title alone, but only a match of the same length: a
      // common title ("Crush") is many songs, and another song's words
      // would be worse than none.
      return pickLyrics(
        await _search({'track_name': song.title}),
        length,
        within: 3,
      );
    } on Object catch (e) {
      debugPrint('Lyrics for ${track.videoId} not found: $e');
      return null; // offline or LRCLIB down: next time
    }
  }

  Future<List<Map<String, Object?>>> _search(Map<String, String> q) async {
    final res = await _client
        .get(
          Uri.https('lrclib.net', '/api/search', q),
          headers: {'User-Agent': 'Idris (https://github.com/isg32/idris)'},
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw HttpException('LRCLIB ${res.statusCode}');
    return [
      for (final r in jsonDecode(utf8.decode(res.bodyBytes)) as List)
        (r as Map).cast<String, Object?>(),
    ];
  }
}

/// From LRCLIB's search results: synced lyrics first, then the closest
/// length to [length] (a video may run longer than the song), then plain
/// lyrics. Instrumentals and empty results give null.
///
/// With [within] (seconds), only a match that close in length counts.
String? pickLyrics(
  List<Map<String, Object?>> results,
  Duration length, {
  double? within,
}) {
  double away(Map<String, Object?> r) {
    final d = (r['duration'] as num?)?.toDouble();
    if (d == null || length == Duration.zero) return 0;
    return (d - length.inMilliseconds / 1000).abs();
  }

  bool has(Map<String, Object?> r, String key) =>
      (r[key] as String?)?.trim().isNotEmpty ?? false;
  final usable = [
    for (final r in results)
      if (r['instrumental'] != true &&
          (has(r, 'syncedLyrics') || has(r, 'plainLyrics')) &&
          (within == null || (r['duration'] != null && away(r) <= within)))
        r,
  ];
  if (usable.isEmpty) return null;
  final synced = [
    for (final r in usable)
      if ((r['syncedLyrics'] as String?)?.trim().isNotEmpty ?? false) r,
  ]..sort((a, b) => away(a).compareTo(away(b)));
  // A synced match much longer or shorter is another version (a live set
  // against the studio song): its times would be wrong.
  if (synced.isNotEmpty && away(synced.first) <= 20) {
    return synced.first['syncedLyrics']! as String;
  }
  usable.sort((a, b) => away(a).compareTo(away(b)));
  return (usable.first['plainLyrics'] as String?) ??
      usable.first['syncedLyrics'] as String?;
}

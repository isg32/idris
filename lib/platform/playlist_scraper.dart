import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'net.dart';
import 'youtube.dart';

/// Reads a playlist's videos straight from YouTube's web pages.
///
/// youtube_explode 3.1.0 only understands the old `playlistVideoRenderer`
/// items; YouTube now sends `lockupViewModel` items, so it finds none.
/// This reads both, and follows the continuation tokens (100 videos a page)
/// through the same `youtubei/v1/browse` endpoint the website uses.
class PlaylistScraper {
  PlaylistScraper({HttpClient? client})
    : _client = client ?? youtubeHttpClient();

  final HttpClient _client;

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) '
      'Gecko/20100101 Firefox/140.0';

  /// Every video in playlist [id], in order.
  Future<List<YtVideo>> videos(String id, {int maxPages = 50}) async {
    // YouTube occasionally answers with a page variant that has no data
    // (a consent or bot check); a second try usually gets the real one.
    late String html;
    Map<String, dynamic>? data;
    for (var attempt = 0; attempt < 3 && data == null; attempt++) {
      html = await _get(
        Uri.parse('https://www.youtube.com/playlist?list=$id&hl=en'),
      );
      data = extractInitialData(html);
    }
    if (data == null) throw const FormatException('No ytInitialData');
    final clientVersion =
        RegExp(r'"INNERTUBE_CLIENT_VERSION":"([^"]+)"').firstMatch(html)?[1] ??
        '2.20260101.00.00';
    final visitor = RegExp(r'"VISITOR_DATA":"([^"]+)"').firstMatch(html)?[1];

    var page = parsePage(data['contents']);
    final out = [...page.videos];
    var token = page.continuation;
    for (var i = 0; token != null && i < maxPages; i++) {
      final more = await _browse(token, clientVersion, visitor);
      page = parsePage(more['onResponseReceivedActions']);
      out.addAll(page.videos);
      token = page.continuation;
    }
    // A video can be in a playlist twice; Idris keeps the first.
    final seen = <String>{};
    return [
      for (final v in out)
        if (seen.add(v.id)) v,
    ];
  }

  Future<String> _get(Uri url) async {
    final req = await _client.getUrl(url);
    req.headers
      ..set(HttpHeaders.userAgentHeader, _ua)
      ..set(HttpHeaders.acceptLanguageHeader, 'en')
      // Skips the EU cookie-consent interstitial.
      ..set(HttpHeaders.cookieHeader, 'SOCS=CAI; CONSENT=YES+1');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${res.statusCode}', uri: url);
    }
    return body;
  }

  Future<Map<String, dynamic>> _browse(
    String token,
    String clientVersion,
    String? visitor,
  ) async {
    final url = Uri.parse(
      'https://www.youtube.com/youtubei/v1/browse?prettyPrint=false',
    );
    final req = await _client.postUrl(url);
    req.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.userAgentHeader, _ua)
      ..set('X-Youtube-Client-Name', '1')
      ..set('X-Youtube-Client-Version', clientVersion);
    if (visitor != null) req.headers.set('X-Goog-Visitor-Id', visitor);
    req.write(
      jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB',
            'clientVersion': clientVersion,
            'hl': 'en',
            'visitorData': ?visitor,
          },
        },
        'continuation': token,
      }),
    );
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${res.statusCode}', uri: url);
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }
}

/// The `ytInitialData` object in a YouTube page, or null.
///
/// YouTube writes it as JSON (`var ytInitialData = {…};`) or, on some
/// responses, as an escaped string (`var ytInitialData = '\x7b…';`).
Map<String, dynamic>? extractInitialData(String html) {
  final m = RegExp(
    r'''(?:var ytInitialData|window\["ytInitialData"\])\s*=\s*''',
  ).firstMatch(html);
  if (m == null) return null;
  final from = m.end;
  try {
    if (html.startsWith("'", from)) {
      final end = html.indexOf("';", from + 1);
      if (end < 0) return null;
      final json = _unescapeJs(html.substring(from + 1, end));
      return jsonDecode(json) as Map<String, dynamic>;
    }
    final end = html.indexOf(';</script>', from);
    if (end < 0) return null;
    return jsonDecode(html.substring(from, end)) as Map<String, dynamic>;
  } on FormatException {
    return null;
  }
}

/// Undoes JavaScript string escapes (`\x7b`, `é`, `\"`, `\\`, `\/`).
String _unescapeJs(String s) =>
    s.replaceAllMapped(RegExp(r'\\(x[0-9a-fA-F]{2}|u[0-9a-fA-F]{4}|.)'), (m) {
      final e = m[1]!;
      if (e.startsWith('x') && e.length == 3) {
        return String.fromCharCode(int.parse(e.substring(1), radix: 16));
      }
      if (e.startsWith('u') && e.length == 5) {
        return String.fromCharCode(int.parse(e.substring(1), radix: 16));
      }
      return switch (e) {
        'n' => '\n',
        't' => '\t',
        'r' => '\r',
        _ => e,
      };
    });

/// One page of a playlist: its videos and the token for the next page.
typedef PlaylistPageItems = ({List<YtVideo> videos, String? continuation});

/// Finds the playlist items (old or new format) and the continuation token
/// anywhere under [node].
PlaylistPageItems parsePage(Object? node) {
  final videos = <YtVideo>[];
  String? token;

  void walk(Object? o) {
    if (o is List) {
      for (final x in o) {
        walk(x);
      }
      return;
    }
    if (o is! Map) return;
    final lockup = o['lockupViewModel'];
    if (lockup is Map) {
      final v = _fromLockup(lockup);
      if (v != null) videos.add(v);
      return;
    }
    final old = o['playlistVideoRenderer'];
    if (old is Map) {
      final v = _fromRenderer(old);
      if (v != null) videos.add(v);
      return;
    }
    for (final e in o.entries) {
      if (e.key == 'continuationItemViewModel' ||
          e.key == 'continuationItemRenderer') {
        token ??= _findToken(e.value);
      } else {
        walk(e.value);
      }
    }
  }

  walk(node);
  return (videos: videos, continuation: token);
}

YtVideo? _fromLockup(Map<dynamic, dynamic> l) {
  if (l['contentType'] != 'LOCKUP_CONTENT_TYPE_VIDEO') return null;
  final id = l['contentId'];
  if (id is! String) return null;
  final meta = _at(l, ['metadata', 'lockupMetadataViewModel']);
  final title = _at(meta, ['title', 'content']);
  final channel = _at(meta, [
    'metadata',
    'contentMetadataViewModel',
    'metadataRows',
    0,
    'metadataParts',
    0,
    'text',
    'content',
  ]);
  // The duration is the badge on the thumbnail ("26:13").
  Duration? duration;
  void find(Object? o) {
    if (duration != null) return;
    if (o is Map) {
      final badge = o['thumbnailBadgeViewModel'];
      if (badge is Map && badge['text'] is String) {
        duration = parseClock(badge['text'] as String);
        if (duration != null) return;
      }
      o.values.forEach(find);
    } else if (o is List) {
      o.forEach(find);
    }
  }

  find(l['contentImage']);
  return YtVideo(
    id: id,
    title: title is String ? title : 'YouTube video',
    channel: channel is String ? channel : '',
    duration: duration ?? Duration.zero,
  );
}

YtVideo? _fromRenderer(Map<dynamic, dynamic> r) {
  final id = r['videoId'];
  if (id is! String) return null;
  final title =
      _at(r, ['title', 'runs', 0, 'text']) ?? _at(r, ['title', 'simpleText']);
  final channel = _at(r, ['shortBylineText', 'runs', 0, 'text']);
  final secs = int.tryParse('${r['lengthSeconds'] ?? ''}');
  return YtVideo(
    id: id,
    title: title is String ? title : 'YouTube video',
    channel: channel is String ? channel : '',
    duration: Duration(seconds: secs ?? 0),
  );
}

String? _findToken(Object? o) {
  if (o is Map) {
    final cmd = o['continuationCommand'];
    if (cmd is Map && cmd['token'] is String) return cmd['token'] as String;
    for (final v in o.values) {
      final t = _findToken(v);
      if (t != null) return t;
    }
  } else if (o is List) {
    for (final v in o) {
      final t = _findToken(v);
      if (t != null) return t;
    }
  }
  return null;
}

Object? _at(Object? o, List<Object> path) {
  var cur = o;
  for (final key in path) {
    if (key is int) {
      if (cur is! List || key >= cur.length) return null;
      cur = cur[key];
    } else {
      if (cur is! Map) return null;
      cur = cur[key];
    }
  }
  return cur;
}

/// `26:13` or `1:02:14` as a duration, else null.
@visibleForTesting
Duration? parseClock(String text) {
  final parts = text.trim().split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  final n = parts.map(int.tryParse).toList();
  if (n.contains(null)) return null;
  return n.length == 2
      ? Duration(minutes: n[0]!, seconds: n[1]!)
      : Duration(hours: n[0]!, minutes: n[1]!, seconds: n[2]!);
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'net.dart';
import 'playlist_scraper.dart';
import 'quality.dart';

const _newPipe = MethodChannel('idris/youtube');

/// youtube_explode on Idris's network route, so a stream link is asked
/// for from the same address that downloads it (see `net.dart`).
YoutubeExplode _yt() =>
    YoutubeExplode(httpClient: YoutubeHttpClient(youtubeClient()));

/// A video in a playlist.
class YtVideo {
  const YtVideo({
    required this.id,
    required this.title,
    required this.channel,
    required this.duration,
  });

  final String id;
  final String title;
  final String channel;
  final Duration duration;
}

/// A playlist as YouTube has it now.
class YtPlaylist {
  const YtPlaylist({
    required this.id,
    required this.title,
    required this.channel,
    required this.videos,
  });

  final String id;
  final String title;
  final String channel;
  final List<YtVideo> videos;
}

/// Why a playlist couldn't be fetched, in words for the import sheet.
class PlaylistError implements Exception {
  const PlaylistError(this.message);
  final String message;

  static const notAPlaylist = PlaylistError('That isn\'t a playlist link.');
  static const unavailable = PlaylistError(
    'This playlist is private or unavailable. Make it public or unlisted.',
  );
  static const offline = PlaylistError('No network. Try again when online.');

  @override
  String toString() => message;
}

/// The playlist ID in a pasted link (or a bare ID), else null.
String? parsePlaylistId(String text) =>
    PlaylistId.parsePlaylistId(text.trim());

/// Fetches a playlist's title and every video in it. Deleted and private
/// videos YouTube still lists are skipped.
Future<YtPlaylist> fetchPlaylist(String idOrUrl) async {
  final id = parsePlaylistId(idOrUrl);
  if (id == null) throw PlaylistError.notAPlaylist;
  final yt = _yt();
  try {
    final Playlist meta;
    try {
      meta = await yt.playlists.get(id);
    } on Object catch (e) {
      debugPrint('Playlist lookup failed: $e');
      throw _isNetwork(e) ? PlaylistError.offline : PlaylistError.unavailable;
    }
    // Idris's own reader first (it knows YouTube's current page format),
    // then youtube_explode's.
    var found = <YtVideo>[];
    try {
      found = await PlaylistScraper().videos(id);
    } on Object catch (e) {
      debugPrint('Playlist reader failed, trying youtube_explode: $e');
    }
    if (found.isEmpty) {
      await for (final v in yt.playlists.getVideos(id)) {
        found.add(
          YtVideo(
            id: v.id.value,
            title: v.title,
            channel: v.author,
            duration: v.duration ?? Duration.zero,
          ),
        );
      }
    }
    final videos = [
      for (final v in found)
        if (!_unplayable.contains(v.title.trim())) v,
    ];
    if (videos.isEmpty && (meta.videoCount ?? 0) > 0) {
      throw const PlaylistError(
        'YouTube says this playlist has videos, but Idris couldn\'t read '
        'them. Try again in a moment.',
      );
    }
    return YtPlaylist(
      id: id,
      title: meta.title,
      channel: meta.author,
      videos: videos,
    );
  } finally {
    yt.close();
  }
}

/// Titles YouTube gives videos that can't be played.
const _unplayable = {'[Deleted video]', '[Private video]'};

bool _isNetwork(Object e) {
  final s = e.toString();
  return s.contains('SocketException') ||
      s.contains('Failed host lookup') ||
      s.contains('ClientException') ||
      s.contains('Connection');
}

/// A playable audio stream for one video.
class ResolvedAudio {
  const ResolvedAudio({
    required this.url,
    required this.kbps,
    required this.mime,
    this.bytes,
  });

  final Uri url;
  final int kbps;
  final String mime;

  /// The file size, when YouTube says.
  final int? bytes;

  String get extension => mime.contains('webm') ? 'webm' : 'm4a';
}

/// One way of finding a video's audio stream.
typedef AudioResolver =
    Future<ResolvedAudio> Function(String videoId, AudioQuality quality);

/// The Dart extractor, asking as [client].
AudioResolver _explode(YoutubeApiClient client) => (id, quality) async {
  final yt = _yt();
  try {
    final manifest = await yt.videos.streamsClient.getManifest(
      VideoId(id),
      ytClients: [client],
    );
    final picked = pickAudio([
      for (final s in manifest.audioOnly)
        if (s.fragments.isEmpty)
          AudioCandidate(
            kbps: s.bitrate.kiloBitsPerSecond,
            m4a: s.container == StreamContainer.mp4,
            value: s,
          ),
    ], quality);
    if (picked == null) throw StateError('No audio-only stream');
    return ResolvedAudio(
      url: picked.url,
      kbps: picked.bitrate.kiloBitsPerSecond.round(),
      mime: picked.container == StreamContainer.mp4
          ? 'audio/mp4'
          : 'audio/webm',
      bytes: picked.size.totalBytes,
    );
  } finally {
    yt.close();
  }
};

/// NewPipe's extractor, on the Android side (`YouTubeChannel.kt`).
Future<ResolvedAudio> _newPipeAudio(String id, AudioQuality quality) async {
  final m = await _newPipe.invokeMapMethod<String, Object?>('audio', {
    'link': 'https://www.youtube.com/watch?v=$id',
    'quality': quality.name,
  });
  final url = m?['url'] as String?;
  if (url == null) throw StateError('NewPipe found no audio');
  return ResolvedAudio(
    url: Uri.parse(url),
    kbps: (m?['bitrate'] as int?) ?? 0,
    mime: (m?['mime'] as String?) ?? 'audio/mp4',
  );
}

/// The ways a stream is found, tried in order.
///
/// NewPipe's extractor comes first: YouTube now serves only the first 1 MB
/// of youtube_explode's Android-client links (then 403 without a
/// proof-of-origin token), and NewPipe's team keeps its links whole. The
/// Dart clients follow for when NewPipe can't find a stream; a link is
/// checked before use (see `CacheManager`).
final List<AudioResolver> audioResolvers = [
  _newPipeAudio,
  _explode(YoutubeApiClient.androidVr),
  _explode(YoutubeApiClient.androidSdkless),
  _explode(YoutubeApiClient.tv),
  _explode(YoutubeApiClient.safari),
  _newPipeAudio,
];

/// Tries [audioResolvers] from [from]; returns the stream and which way
/// found it.
Future<(ResolvedAudio, int)> resolveAudio(
  String videoId,
  AudioQuality quality, {
  int from = 0,
  List<AudioResolver>? resolvers,
}) async {
  final ways = resolvers ?? audioResolvers;
  Object? last;
  for (var i = from; i < ways.length; i++) {
    try {
      return (await ways[i](videoId, quality), i);
    } on Object catch (e) {
      debugPrint('YouTube way ${i + 1} failed for $videoId: $e');
      last = e;
    }
  }
  throw StateError('No way to stream $videoId: $last');
}

/// The video's page, for "Open on YouTube".
Uri watchUrl(String videoId) =>
    Uri.parse('https://www.youtube.com/watch?v=$videoId');

/// The video's thumbnail (lock-screen artwork).
Uri thumbnailUrl(String videoId) =>
    Uri.parse('https://i.ytimg.com/vi/$videoId/hqdefault.jpg');

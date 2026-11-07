import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/db/database.dart';
import '../data/library.dart';
import 'cache_download.dart';
import 'quality.dart';
import 'youtube.dart';

/// What playback opened: the source, and how it was found.
class OpenedAudio {
  const OpenedAudio({
    required this.source,
    required this.cached,
    required this.kbps,
    this.resolver = 0,
  });

  final AudioSource source;

  /// Playing from a complete file on the phone.
  final bool cached;
  final int kbps;

  /// Which [audioResolvers] entry found the stream (for recovery).
  final int resolver;
}

/// The audio cache: every played track is kept, pinned tracks are fetched
/// ahead (on Wi-Fi by default), and unpinned tracks are removed, least
/// recently played first, when the cache passes its limit.
class CacheManager {
  CacheManager(
    this.library, {
    Directory? dir,
    Stream<List<ConnectivityResult>>? connectivity,
    Future<List<ConnectivityResult>> Function()? checkConnectivity,
    this.resolve = resolveAudio,
  }) : _dirOverride = dir,
       _connectivity =
           connectivity ?? Connectivity().onConnectivityChanged,
       _checkConnectivity =
           checkConnectivity ?? Connectivity().checkConnectivity;

  final Library library;
  final Future<(ResolvedAudio, int)> Function(
    String videoId,
    AudioQuality quality, {
    int from,
    List<AudioResolver>? resolvers,
  })
  resolve;

  final Directory? _dirOverride;
  Directory? _dir;
  final Stream<List<ConnectivityResult>> _connectivity;
  final Future<List<ConnectivityResult>> Function() _checkConnectivity;

  /// Downloads running now, by video ID.
  final Map<String, CacheDownload> _active = {};

  /// Download progress (0–1) of tracks being cached, for the rows.
  final ValueNotifier<Map<String, double>> progress = ValueNotifier(const {});

  /// Why pinned tracks aren't downloading, if they aren't.
  final ValueNotifier<String?> waitingReason = ValueNotifier(null);

  /// The video playing now (never evicted or pre-empted).
  String? playingId;

  StreamSubscription<Object?>? _pinSub;
  StreamSubscription<Object?>? _netSub;
  bool _working = false;
  bool _wanted = false;
  Timer? _tick;

  Future<Directory> get dir async {
    final d = _dir ??= _dirOverride ?? Directory(
      p.join((await getApplicationSupportDirectory()).path, 'audio'),
    );
    if (!d.existsSync()) await d.create(recursive: true);
    return d;
  }

  /// Starts watching pins and the network for pre-caching.
  void startWorker() {
    _pinSub ??= library.watchPinnedVideoIds().listen((_) => kick());
    _netSub ??= _connectivity.listen((_) => kick());
    _tick ??= Timer.periodic(const Duration(milliseconds: 500), (_) {
      _publishProgress();
    });
  }

  void dispose() {
    _pinSub?.cancel();
    _netSub?.cancel();
    _tick?.cancel();
    for (final d in _active.values) {
      d.cancel();
    }
  }

  void _publishProgress() {
    final now = {
      for (final e in _active.entries)
        if (!e.value.isComplete && e.value.error == null)
          e.key: e.value.progress,
    };
    if (!mapEquals(now, progress.value)) progress.value = now;
  }

  // ------------------------------------------------------------- playback

  /// The audio for [videoId]: the cached file when it's complete, else a
  /// stream that caches as it plays. [from] skips resolvers that already
  /// failed (recovery).
  Future<OpenedAudio> open(
    String videoId,
    AudioQuality quality, {
    int from = 0,
  }) async {
    final entry = await library.cacheEntry(videoId);
    if (entry != null && entry.complete && from == 0) {
      final f = File(entry.path);
      if (f.existsSync()) {
        return OpenedAudio(
          source: AudioSource.file(f.path),
          cached: true,
          kbps: entry.kbps,
        );
      }
      await library.deleteCache(videoId);
    }
    final running = _active[videoId];
    if (running != null && running.error == null && from == 0) {
      return OpenedAudio(
        source: CachingAudioSource(running),
        cached: false,
        kbps: entry?.kbps ?? 0,
      );
    }
    final (audio, way) = await resolve(videoId, quality, from: from);
    final download = await _begin(videoId, audio);
    return OpenedAudio(
      source: CachingAudioSource(download),
      cached: false,
      kbps: audio.kbps,
      resolver: way,
    );
  }

  /// Starts (or restarts, with a fresh link) the download of [videoId].
  Future<CacheDownload> _begin(String videoId, ResolvedAudio audio) async {
    _active.remove(videoId)?.cancel();
    final d = await dir;
    final path = p.join(d.path, '$videoId.${audio.extension}');
    final part = File('$path.part');
    // A partial file from another stream (another quality or format)
    // can't be resumed.
    final old = await library.cacheEntry(videoId);
    if (old != null && old.path != path) {
      await _deleteFiles(old.path);
    }
    final total = audio.bytes ?? await CacheDownload.fetchLength(audio.url);
    if (part.existsSync() && part.lengthSync() > total) {
      await part.delete();
    }
    final download = CacheDownload(
      videoId: videoId,
      url: audio.url,
      partFile: part,
      total: total,
      mime: audio.mime,
    );
    _active[videoId] = download;
    await library.putCache(
      CacheEntriesCompanion.insert(
        videoId: videoId,
        path: path,
        bytes: Value(download.written),
        totalBytes: Value(total),
        kbps: Value(audio.kbps),
        mime: Value(audio.mime),
        lastPlayedAt: Value(old?.lastPlayedAt),
        cachedAt: DateTime.now(),
      ),
    );
    download.start();
    unawaited(
      download.done.then(
        (_) => _finish(videoId, download, path),
        onError: (Object _) {
          if (identical(_active[videoId], download)) _active.remove(videoId);
        },
      ),
    );
    return download;
  }

  Future<void> _finish(String videoId, CacheDownload d, String path) async {
    if (identical(_active[videoId], d)) _active.remove(videoId);
    try {
      await d.partFile.rename(path);
      await library.updateCache(
        videoId,
        CacheEntriesCompanion(
          bytes: Value(d.total),
          complete: const Value(true),
        ),
      );
    } on Object catch (e) {
      debugPrint('Caching $videoId failed at the end: $e');
    }
    _publishProgress();
    await evict();
    kick();
  }

  /// Notes that [videoId] just started playing (keeps it out of eviction
  /// longest).
  Future<void> touch(String videoId) async {
    playingId = videoId;
    await library.updateCache(
      videoId,
      CacheEntriesCompanion(lastPlayedAt: Value(DateTime.now())),
    );
  }

  // ------------------------------------------------------------ pre-cache

  /// Looks for pinned tracks to fetch, if the network allows.
  void kick() {
    _wanted = true;
    if (!_working) unawaited(_work());
  }

  Future<bool> _networkAllows() async {
    final s = await library.settings();
    final net = await _checkConnectivity();
    if (net.isEmpty || net.every((n) => n == ConnectivityResult.none)) {
      waitingReason.value = 'waiting for a network';
      return false;
    }
    final unmetered =
        net.contains(ConnectivityResult.wifi) ||
        net.contains(ConnectivityResult.ethernet);
    if (s.precacheWifiOnly && !unmetered) {
      waitingReason.value = 'waiting for Wi-Fi';
      return false;
    }
    waitingReason.value = null;
    return true;
  }

  Future<void> _work() async {
    _working = true;
    try {
      while (_wanted) {
        _wanted = false;
        final pinned = await library.pinnedVideoIds();
        final entries = {
          for (final e in await library.cacheEntries()) e.videoId: e,
        };
        final todo = [
          for (final id in pinned)
            if (entries[id]?.complete != true) id,
        ];
        if (todo.isEmpty) {
          waitingReason.value = null;
          break;
        }
        for (final id in todo) {
          if (!await _networkAllows()) break;
          if (await library.track(id) == null) continue;
          final running = _active[id];
          try {
            if (running != null && running.error == null) {
              await running.done;
            } else {
              final s = await library.settings();
              final (audio, _) = await resolve(id, s.quality);
              final d = await _begin(id, audio);
              await d.done;
            }
          } on Object catch (e) {
            debugPrint('Pre-caching $id failed: $e');
          }
        }
      }
    } finally {
      _working = false;
    }
  }

  // ------------------------------------------------------------- eviction

  /// Removes unpinned audio, least recently played first, until the auto
  /// cache fits the limit.
  Future<void> evict() async {
    final s = await library.settings();
    final limit = s.cacheLimitBytes;
    if (limit == null) return;
    final doomed = chooseEvictions(
      await library.cacheEntries(),
      pinned: await library.pinnedVideoIds(),
      keep: {?playingId, ..._active.keys},
      limitBytes: limit,
    );
    for (final e in doomed) {
      await remove(e.videoId);
    }
  }

  /// Deletes [videoId]'s audio (and stops caching it).
  Future<void> remove(String videoId) async {
    _active.remove(videoId)?.cancel();
    final e = await library.cacheEntry(videoId);
    if (e != null) await _deleteFiles(e.path);
    await library.deleteCache(videoId);
    _publishProgress();
  }

  /// Deletes all unpinned audio (Settings → Clear auto cache).
  Future<void> clearAuto() async {
    final pinned = await library.pinnedVideoIds();
    for (final e in await library.cacheEntries()) {
      if (pinned.contains(e.videoId) || e.videoId == playingId) continue;
      await remove(e.videoId);
    }
  }

  Future<void> _deleteFiles(String path) async {
    for (final f in [File(path), File('$path.part')]) {
      try {
        if (f.existsSync()) await f.delete();
      } on Object catch (e) {
        debugPrint('Could not delete $f: $e');
      }
    }
  }
}

/// The cache entries to delete so the unpinned ones total at most
/// [limitBytes]: least recently played first (never-played by when they
/// were cached). Pinned and [keep] entries are never chosen.
List<CacheEntry> chooseEvictions(
  List<CacheEntry> entries, {
  required Set<String> pinned,
  required Set<String> keep,
  required int limitBytes,
}) {
  final auto = [
    for (final e in entries)
      if (!pinned.contains(e.videoId)) e,
  ];
  var total = auto.fold<int>(0, (sum, e) => sum + e.bytes);
  if (total <= limitBytes) return const [];
  final candidates = [
    for (final e in auto)
      if (!keep.contains(e.videoId)) e,
  ]..sort((a, b) => (a.lastPlayedAt ?? a.cachedAt).compareTo(
      b.lastPlayedAt ?? b.cachedAt,
    ));
  final out = <CacheEntry>[];
  for (final e in candidates) {
    if (total <= limitBytes) break;
    out.add(e);
    total -= e.bytes;
  }
  return out;
}

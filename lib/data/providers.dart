import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../platform/audio_handler.dart';
import '../platform/cache_manager.dart';
import '../platform/covers.dart';
import '../platform/glyph.dart';
import '../platform/local_music.dart';
import '../platform/lyrics.dart';
import '../platform/youtube.dart';
import 'library.dart';
import 'models.dart';

/// Set in main() (overridden), so the media service and the pages share
/// one library, cache and player.
final libraryProvider = Provider<Library>(
  (ref) => throw UnimplementedError('libraryProvider is set in main()'),
);
final cacheManagerProvider = Provider<CacheManager>(
  (ref) => throw UnimplementedError('cacheManagerProvider is set in main()'),
);
final audioHandlerProvider = Provider<IdrisAudioHandler>(
  (ref) => throw UnimplementedError('audioHandlerProvider is set in main()'),
);

// ------------------------------------------------------------------ library

final playlistsProvider = StreamProvider<List<PlaylistSummary>>(
  (ref) => ref.watch(libraryProvider).watchPlaylists(),
);

final playlistProvider = StreamProvider.family<Playlist?, int>(
  (ref, id) => ref.watch(libraryProvider).watchPlaylist(id),
);

final playlistTracksProvider = StreamProvider.family<List<Track>, int>(
  (ref, id) => ref.watch(libraryProvider).watchPlaylistTracks(id),
);

final recentlyAddedProvider = StreamProvider<List<TrackInPlaylist>>(
  (ref) => ref.watch(libraryProvider).watchRecentlyAdded(),
);

final recentlyPlayedProvider = StreamProvider<List<TrackInPlaylist>>(
  (ref) => ref.watch(libraryProvider).watchRecentlyPlayed(),
);

final settingsProvider = StreamProvider<Settings>(
  (ref) => ref.watch(libraryProvider).watchSettings(),
);

// -------------------------------------------------------------------- cache

final cacheEntriesProvider = StreamProvider<Map<String, CacheEntry>>(
  (ref) => ref.watch(libraryProvider).watchCache(),
);

final pinnedIdsProvider = StreamProvider<Set<String>>(
  (ref) => ref.watch(libraryProvider).watchPinnedVideoIds(),
);

/// Bytes cached: pinned and auto (unpinned), complete files only.
final storageProvider = Provider<({int pinned, int auto})>((ref) {
  final entries = ref.watch(cacheEntriesProvider).value ?? const {};
  final pinned = ref.watch(pinnedIdsProvider).value ?? const <String>{};
  var p = 0, a = 0;
  for (final e in entries.values) {
    if (pinned.contains(e.videoId)) {
      p += e.bytes;
    } else {
      a += e.bytes;
    }
  }
  return (pinned: p, auto: a);
});

/// Download progress of tracks being cached right now.
final cacheProgressProvider = Provider<Map<String, double>>((ref) {
  final n = ref.watch(cacheManagerProvider).progress;
  void changed() => ref.invalidateSelf();
  n.addListener(changed);
  ref.onDispose(() => n.removeListener(changed));
  return n.value;
});

/// Why pinned tracks are waiting ("waiting for Wi-Fi"), if they are.
final precacheWaitingProvider = Provider<String?>((ref) {
  final n = ref.watch(cacheManagerProvider).waitingReason;
  void changed() => ref.invalidateSelf();
  n.addListener(changed);
  ref.onDispose(() => n.removeListener(changed));
  return n.value;
});

/// The state a track row shows.
enum TrackCacheState { streams, caching, cached, pinned, local }

final trackCacheStateProvider = Provider.family<TrackCacheState, String>((
  ref,
  videoId,
) {
  if (isLocal(videoId)) return TrackCacheState.local;
  final entry = ref.watch(cacheEntriesProvider).value?[videoId];
  final pinned = ref.watch(pinnedIdsProvider).value?.contains(videoId) ?? false;
  final caching = ref.watch(cacheProgressProvider).containsKey(videoId);
  if (entry?.complete == true) {
    return pinned ? TrackCacheState.pinned : TrackCacheState.cached;
  }
  if (caching) return TrackCacheState.caching;
  return TrackCacheState.streams;
});

/// "On this phone": music from folders the user chose.
final localMusicProvider = Provider<LocalMusic>(
  (ref) => throw UnimplementedError('overridden in main()'),
);

final localFoldersProvider = StreamProvider<List<LocalFolder>>(
  (ref) => ref.watch(localMusicProvider).watchFolders(),
);

final localTracksProvider = StreamProvider<List<Track>>(
  (ref) => ref.watch(localMusicProvider).watchTracks(),
);

/// Songs per chosen folder, by folder URI.
final localCountsProvider = StreamProvider<Map<String, int>>(
  (ref) => ref.watch(localMusicProvider).watchCounts(),
);

/// Lyrics, from an .lrc beside a local file or LRCLIB, kept for offline.
final lyricsServiceProvider = Provider<LyricsService>(
  (ref) => throw UnimplementedError('overridden in main()'),
);

/// A track's lyrics, or null when there are none.
final lyricsProvider = FutureProvider.family<Lyrics?, String>((
  ref,
  videoId,
) async {
  final track = await ref.watch(libraryProvider).track(videoId);
  if (track == null) return null;
  return ref.watch(lyricsServiceProvider).lyricsFor(track);
});

/// Whether the phone's player shows the lyrics instead of the track.
final lyricsOpenProvider = NotifierProvider<LyricsOpen, bool>(LyricsOpen.new);

class LyricsOpen extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

/// Where the covers the user chose are kept.
final coversProvider = Provider<Covers>((ref) => Covers());

final trackProvider = StreamProvider.family<Track?, String>(
  (ref, videoId) => ref.watch(libraryProvider).watchTrack(videoId),
);

/// A track's cover: the one the user chose, else (when Settings → Artwork
/// is on) YouTube's picture, saved beside the audio; else none (the
/// waveform tile shows instead).
final artworkProvider = FutureProvider.family<File?, String>((ref, videoId) {
  final chosen = ref.watch(trackProvider(videoId)).value?.coverPath;
  if (chosen != null && File(chosen).existsSync()) {
    return Future.value(File(chosen));
  }
  final on = ref.watch(settingsProvider).value?.artwork ?? true;
  if (!on) return Future.value();
  return ref.watch(cacheManagerProvider).artwork(videoId);
});

// ------------------------------------------------------------------ network

final connectivityProvider = StreamProvider<bool>((ref) async* {
  final c = Connectivity();
  bool online(List<ConnectivityResult> r) =>
      r.any((x) => x != ConnectivityResult.none);
  yield online(await c.checkConnectivity());
  yield* c.onConnectivityChanged.map(online);
});

// ------------------------------------------------------------------- player

/// The session, for the pages.
final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(
  SessionNotifier.new,
);

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() {
    final handler = ref.watch(audioHandlerProvider);
    void changed() => state = handler.session.value;
    handler.session.addListener(changed);
    ref.onDispose(() => handler.session.removeListener(changed));
    return handler.session.value;
  }
}

final playingProvider = StreamProvider<bool>(
  (ref) => ref.watch(audioHandlerProvider).player.playingStream,
);

final positionProvider = StreamProvider<Duration>(
  (ref) => ref.watch(audioHandlerProvider).player.positionStream,
);

final durationProvider = StreamProvider<Duration?>(
  (ref) => ref.watch(audioHandlerProvider).player.durationStream,
);

final processingProvider = StreamProvider<ProcessingState>(
  (ref) => ref.watch(audioHandlerProvider).player.processingStateStream,
);

// --------------------------------------------------------------------- sync

/// Re-fetches every playlist from YouTube. Offline, it does nothing.
final syncProvider = Provider<Future<SyncResult> Function()>((ref) {
  return () async {
    final library = ref.read(libraryProvider);
    var total = SyncResult.none;
    for (final p in await library.allPlaylists()) {
      try {
        final yt = await fetchPlaylist(p.ytId);
        total += await library.syncPlaylist(p.id, yt);
      } on Object catch (e) {
        debugPrint('Sync of ${p.title} skipped: $e');
      }
    }
    try {
      // New and changed files in the folders on the phone.
      await ref.read(localMusicProvider).scanAll();
    } on Object catch (e) {
      debugPrint('Rescan of folders on the phone skipped: $e');
    }
    ref.read(cacheManagerProvider).kick();
    return total;
  };
});

/// Re-fetches one playlist.
final syncOneProvider = Provider<Future<SyncResult> Function(int id)>((ref) {
  return (id) async {
    final library = ref.read(libraryProvider);
    final p = await library.watchPlaylist(id).first;
    if (p == null) return SyncResult.none;
    try {
      final r = await library.syncPlaylist(id, await fetchPlaylist(p.ytId));
      ref.read(cacheManagerProvider).kick();
      return r;
    } on Object catch (e) {
      debugPrint('Sync of ${p.title} skipped: $e');
      return SyncResult.none;
    }
  };
});

/// The last sync's outcome, for "Synced · 2 new" on Home.
final lastSyncProvider = NotifierProvider<LastSync, SyncResult?>(LastSync.new);

class LastSync extends Notifier<SyncResult?> {
  @override
  SyncResult? build() => null;

  void set(SyncResult r) => state = r;
}

// -------------------------------------------------------------------- glyph

final glyphAvailableProvider = FutureProvider<bool>(
  (ref) => GlyphBreath.instance.available,
);

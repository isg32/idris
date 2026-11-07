import '../platform/quality.dart';
import 'db/database.dart';

export 'db/database.dart' show Track, CacheEntry, Playlist;

/// A playlist with the numbers its card shows.
class PlaylistSummary {
  const PlaylistSummary({
    required this.playlist,
    required this.trackCount,
    required this.total,
    required this.cachedCount,
  });

  final Playlist playlist;
  final int trackCount;
  final Duration total;

  /// Tracks fully cached (playable offline).
  final int cachedCount;

  int get id => playlist.id;
  String get title => playlist.title;
  bool get pinned => playlist.pinned;
  bool get allCached => trackCount > 0 && cachedCount >= trackCount;
}

/// A track with the playlist it was found through (Home sections).
class TrackInPlaylist {
  const TrackInPlaylist({
    required this.track,
    required this.playlistId,
    required this.playlistTitle,
    required this.at,
    this.isNew = false,
  });

  final Track track;
  final int playlistId;
  final String playlistTitle;

  /// When it was added (Recently added) or played (Recently played).
  final DateTime at;

  /// Added after the playlist was first imported.
  final bool isNew;
}

/// What happened in a sync.
class SyncResult {
  const SyncResult({required this.added, required this.removed});
  final int added;
  final int removed;

  static const none = SyncResult(added: 0, removed: 0);

  SyncResult operator +(SyncResult o) =>
      SyncResult(added: added + o.added, removed: removed + o.removed);
}

/// What a repeat count does when it's done.
enum RepeatEnd { stop, next }

/// Everything in Settings.
class Settings {
  const Settings({
    this.quality = AudioQuality.best,
    this.cacheLimitGb = defaultCacheLimitGb,
    this.precacheWifiOnly = true,
    this.glyph = false,
    this.repeatEnd = RepeatEnd.next,
    this.syncOnOpen = true,
  });

  static const int defaultCacheLimitGb = 5;

  /// The cache limit steps; 0 means unlimited.
  static const List<int> cacheLimitSteps = [1, 2, 5, 10, 0];

  final AudioQuality quality;

  /// Limit for auto-cached (unpinned) audio, in GB; 0 = unlimited.
  final int cacheLimitGb;
  final bool precacheWifiOnly;
  final bool glyph;
  final RepeatEnd repeatEnd;
  final bool syncOnOpen;

  int? get cacheLimitBytes =>
      cacheLimitGb == 0 ? null : cacheLimitGb * 1024 * 1024 * 1024;

  static Settings fromPrefs(Map<String, String> p) => Settings(
    quality: AudioQuality.parse(p['quality']),
    cacheLimitGb:
        int.tryParse(p['cacheLimitGb'] ?? '') ?? defaultCacheLimitGb,
    precacheWifiOnly: p['precacheWifiOnly'] != 'false',
    glyph: p['glyph'] == 'true',
    repeatEnd: p['repeatEnd'] == 'stop' ? RepeatEnd.stop : RepeatEnd.next,
    syncOnOpen: p['syncOnOpen'] != 'false',
  );
}

/// The changes that turn [current] (video IDs in the playlist now, in
/// Idris) into [incoming] (as on YouTube).
({List<String> added, List<String> removed}) diffPlaylist(
  List<String> current,
  List<String> incoming,
) {
  final have = current.toSet();
  final want = incoming.toSet();
  return (
    added: [
      for (final id in incoming)
        if (!have.contains(id)) id,
    ],
    removed: [
      for (final id in current)
        if (!want.contains(id)) id,
    ],
  );
}

import 'dart:convert';

import 'package:drift/drift.dart';

import '../platform/youtube.dart';
import 'db/database.dart';
import 'models.dart';

/// Everything Idris stores: playlists, tracks, plays, the cache index and
/// settings.
class Library {
  Library(this.db);

  final AppDatabase db;

  // ---------------------------------------------------------------- playlists

  /// The playlist with this YouTube ID, if imported.
  Future<Playlist?> byYtId(String ytId) => (db.select(
    db.playlists,
  )..where((p) => p.ytId.equals(ytId))).getSingleOrNull();

  Future<List<Playlist>> allPlaylists() => db.select(db.playlists).get();

  /// Adds [yt] (or syncs it when already imported); returns its ID.
  Future<int> importPlaylist(YtPlaylist yt, {DateTime? now}) async {
    final existing = await byYtId(yt.id);
    if (existing != null) {
      await syncPlaylist(existing.id, yt, now: now);
      return existing.id;
    }
    final at = now ?? DateTime.now();
    return db.transaction(() async {
      final id = await db
          .into(db.playlists)
          .insert(
            PlaylistsCompanion.insert(
              ytId: yt.id,
              title: yt.title,
              channel: Value(yt.channel),
              importedAt: at,
              lastSyncedAt: Value(at),
            ),
          );
      await _writeTracks(id, yt.videos, at, existing: const {});
      return id;
    });
  }

  /// Brings playlist [id] in line with YouTube's [yt]: new videos are
  /// added (and show under Recently added), removed ones dropped. Their
  /// cached audio stays until the cache needs the room.
  Future<SyncResult> syncPlaylist(
    int id,
    YtPlaylist yt, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    return db.transaction(() async {
      final rows = await (db.select(
        db.playlistTracks,
      )..where((t) => t.playlistId.equals(id))).get();
      final existing = {for (final r in rows) r.videoId: r.firstSeenAt};
      final diff = diffPlaylist(
        rows.map((r) => r.videoId).toList(),
        yt.videos.map((v) => v.id).toList(),
      );
      if (diff.removed.isNotEmpty) {
        await (db.delete(db.playlistTracks)..where(
              (t) => t.playlistId.equals(id) & t.videoId.isIn(diff.removed),
            ))
            .go();
      }
      await _writeTracks(id, yt.videos, at, existing: existing);
      await (db.update(db.playlists)..where((p) => p.id.equals(id))).write(
        // The title isn't touched: it may have been renamed in Idris.
        PlaylistsCompanion(channel: Value(yt.channel), lastSyncedAt: Value(at)),
      );
      await _dropOrphans();
      return SyncResult(added: diff.added.length, removed: diff.removed.length);
    });
  }

  Future<void> _writeTracks(
    int playlistId,
    List<YtVideo> videos,
    DateTime at, {
    required Map<String, DateTime> existing,
  }) async {
    await db.batch((b) {
      for (final (i, v) in videos.indexed) {
        b.insert(
          db.tracks,
          TracksCompanion.insert(
            videoId: v.id,
            title: v.title,
            channel: Value(v.channel),
            durationMs: Value(v.duration.inMilliseconds),
          ),
          onConflict: DoUpdate(
            (_) => TracksCompanion(
              title: Value(v.title),
              channel: Value(v.channel),
              durationMs: Value(v.duration.inMilliseconds),
            ),
          ),
        );
        b.insert(
          db.playlistTracks,
          PlaylistTracksCompanion.insert(
            playlistId: playlistId,
            videoId: v.id,
            position: i,
            firstSeenAt: existing[v.id] ?? at,
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  /// Tracks no playlist holds any more.
  Future<void> _dropOrphans() => db.customStatement(
    'DELETE FROM tracks WHERE video_id NOT IN '
    '(SELECT video_id FROM playlist_tracks)',
  );

  Future<void> renamePlaylist(int id, String title) =>
      (db.update(db.playlists)..where((p) => p.id.equals(id))).write(
        PlaylistsCompanion(title: Value(title)),
      );

  Future<void> removePlaylist(int id) => db.transaction(() async {
    await (db.delete(
      db.playlistTracks,
    )..where((t) => t.playlistId.equals(id))).go();
    await (db.delete(db.playlists)..where((p) => p.id.equals(id))).go();
    await _dropOrphans();
  });

  Future<void> setPlaylistPinned(int id, bool pinned) =>
      (db.update(db.playlists)..where((p) => p.id.equals(id))).write(
        PlaylistsCompanion(pinned: Value(pinned)),
      );

  Future<void> setTrackPinned(String videoId, bool pinned) =>
      (db.update(db.tracks)..where((t) => t.videoId.equals(videoId))).write(
        TracksCompanion(pinned: Value(pinned)),
      );

  /// Playlists with their card numbers, newest import first.
  Stream<List<PlaylistSummary>> watchPlaylists() {
    final query = db.customSelect(
      'SELECT p.*, '
      '  COUNT(pt.video_id) AS n, '
      '  COALESCE(SUM(t.duration_ms), 0) AS ms, '
      '  COALESCE(SUM(CASE WHEN c.complete = 1 THEN 1 ELSE 0 END), 0) AS cached '
      'FROM playlists p '
      'LEFT JOIN playlist_tracks pt ON pt.playlist_id = p.id '
      'LEFT JOIN tracks t ON t.video_id = pt.video_id '
      'LEFT JOIN cache_entries c ON c.video_id = pt.video_id '
      'GROUP BY p.id ORDER BY p.imported_at DESC',
      readsFrom: {db.playlists, db.playlistTracks, db.tracks, db.cacheEntries},
    );
    return query.watch().map(
      (rows) => [
        for (final r in rows)
          PlaylistSummary(
            playlist: db.playlists.map(r.data),
            trackCount: r.read<int>('n'),
            total: Duration(milliseconds: r.read<int>('ms')),
            cachedCount: r.read<int>('cached'),
          ),
      ],
    );
  }

  Stream<Playlist?> watchPlaylist(int id) => (db.select(
    db.playlists,
  )..where((p) => p.id.equals(id))).watchSingleOrNull();

  /// A playlist's tracks, in YouTube's order.
  Stream<List<Track>> watchPlaylistTracks(int id) {
    final q =
        db.select(db.playlistTracks).join([
            innerJoin(
              db.tracks,
              db.tracks.videoId.equalsExp(db.playlistTracks.videoId),
            ),
          ])
          ..where(db.playlistTracks.playlistId.equals(id))
          ..orderBy([OrderingTerm.asc(db.playlistTracks.position)]);
    return q.watch().map(
      (rows) => [for (final r in rows) r.readTable(db.tracks)],
    );
  }

  Future<List<Track>> playlistTracks(int id) => watchPlaylistTracks(id).first;

  /// The newest tracks across playlists.
  Stream<List<TrackInPlaylist>> watchRecentlyAdded({int limit = 10}) {
    final q =
        db.select(db.playlistTracks).join([
            innerJoin(
              db.tracks,
              db.tracks.videoId.equalsExp(db.playlistTracks.videoId),
            ),
            innerJoin(
              db.playlists,
              db.playlists.id.equalsExp(db.playlistTracks.playlistId),
            ),
          ])
          ..orderBy([
            OrderingTerm.desc(db.playlistTracks.firstSeenAt),
            OrderingTerm.desc(db.playlistTracks.position),
          ])
          ..limit(limit * 3);
    return q.watch().map((rows) {
      final seen = <String>{};
      final out = <TrackInPlaylist>[];
      for (final r in rows) {
        final t = r.readTable(db.tracks);
        if (!seen.add(t.videoId)) continue;
        final pt = r.readTable(db.playlistTracks);
        final p = r.readTable(db.playlists);
        out.add(
          TrackInPlaylist(
            track: t,
            playlistId: p.id,
            playlistTitle: p.title,
            at: pt.firstSeenAt,
            isNew: pt.firstSeenAt.isAfter(p.importedAt),
          ),
        );
        if (out.length == limit) break;
      }
      return out;
    });
  }

  /// The last tracks played, each once.
  Stream<List<TrackInPlaylist>> watchRecentlyPlayed({int limit = 8}) {
    final query = db.customSelect(
      'SELECT t.*, MAX(pl.played_at) AS at, '
      '  (SELECT pt.playlist_id FROM playlist_tracks pt '
      '     WHERE pt.video_id = t.video_id LIMIT 1) AS pid, '
      '  (SELECT p.title FROM playlist_tracks pt JOIN playlists p '
      '     ON p.id = pt.playlist_id WHERE pt.video_id = t.video_id LIMIT 1) '
      '     AS ptitle '
      'FROM plays pl JOIN tracks t ON t.video_id = pl.video_id '
      'GROUP BY t.video_id ORDER BY at DESC LIMIT ?',
      variables: [Variable.withInt(limit)],
      readsFrom: {db.plays, db.tracks, db.playlistTracks, db.playlists},
    );
    return query.watch().map(
      (rows) => [
        for (final r in rows)
          TrackInPlaylist(
            track: db.tracks.map(r.data),
            playlistId: r.read<int?>('pid') ?? 0,
            playlistTitle: r.read<String?>('ptitle') ?? '',
            at: DateTime.fromMillisecondsSinceEpoch(r.read<int>('at') * 1000),
          ),
      ],
    );
  }

  Future<void> recordPlay(String videoId, {DateTime? at}) => db
      .into(db.plays)
      .insert(
        PlaysCompanion.insert(videoId: videoId, playedAt: at ?? DateTime.now()),
      );

  Future<Track?> track(String videoId) => (db.select(
    db.tracks,
  )..where((t) => t.videoId.equals(videoId))).getSingleOrNull();

  Future<void> setDuration(String videoId, Duration d) =>
      (db.update(db.tracks)..where((t) => t.videoId.equals(videoId))).write(
        TracksCompanion(durationMs: Value(d.inMilliseconds)),
      );

  // -------------------------------------------------------------------- cache

  Stream<Map<String, CacheEntry>> watchCache() => db
      .select(db.cacheEntries)
      .watch()
      .map((rows) => {for (final r in rows) r.videoId: r});

  Future<List<CacheEntry>> cacheEntries() => db.select(db.cacheEntries).get();

  Future<CacheEntry?> cacheEntry(String videoId) => (db.select(
    db.cacheEntries,
  )..where((c) => c.videoId.equals(videoId))).getSingleOrNull();

  Future<void> putCache(CacheEntriesCompanion entry) =>
      db.into(db.cacheEntries).insert(entry, mode: InsertMode.insertOrReplace);

  Future<void> updateCache(String videoId, CacheEntriesCompanion change) =>
      (db.update(
        db.cacheEntries,
      )..where((c) => c.videoId.equals(videoId))).write(change);

  Future<void> deleteCache(String videoId) => (db.delete(
    db.cacheEntries,
  )..where((c) => c.videoId.equals(videoId))).go();

  /// Video IDs that must stay cached: pinned on their own, or in a pinned
  /// playlist.
  Future<Set<String>> pinnedVideoIds() => watchPinnedVideoIds().first;

  Stream<Set<String>> watchPinnedVideoIds() {
    final query = db.customSelect(
      'SELECT video_id FROM tracks WHERE pinned = 1 '
      'UNION SELECT pt.video_id FROM playlist_tracks pt '
      'JOIN playlists p ON p.id = pt.playlist_id WHERE p.pinned = 1',
      readsFrom: {db.tracks, db.playlistTracks, db.playlists},
    );
    return query.watch().map(
      (rows) => {for (final r in rows) r.read<String>('video_id')},
    );
  }

  // -------------------------------------------------------------------- prefs

  Stream<Settings> watchSettings() => db
      .select(db.prefs)
      .watch()
      .map(
        (rows) => Settings.fromPrefs({for (final r in rows) r.key: r.value}),
      );

  Future<Settings> settings() => watchSettings().first;

  Future<void> setPref(String key, String value) => db
      .into(db.prefs)
      .insert(
        PrefsCompanion.insert(key: key, value: value),
        mode: InsertMode.insertOrReplace,
      );

  // ------------------------------------------------------------ export/import

  /// The library as JSON: the playlists (YouTube IDs and titles) and what is
  /// pinned. Audio isn't included; it re-caches.
  Future<String> exportJson() async {
    final playlists = await allPlaylists();
    final pinnedTracks = await (db.select(
      db.tracks,
    )..where((t) => t.pinned.equals(true))).get();
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'idris',
      'version': 1,
      'playlists': [
        for (final p in playlists)
          {'id': p.ytId, 'title': p.title, 'pinned': p.pinned},
      ],
      'pinnedTracks': [for (final t in pinnedTracks) t.videoId],
    });
  }

  /// The playlist IDs (and pinned flags) in an export.
  static List<({String id, bool pinned})> parseExport(String json) {
    final data = jsonDecode(json);
    if (data is! Map || data['app'] != 'idris') {
      throw const FormatException('Not an Idris library file');
    }
    final list = data['playlists'];
    if (list is! List) return const [];
    return [
      for (final p in list)
        if (p is Map && p['id'] is String)
          (id: p['id'] as String, pinned: p['pinned'] == true),
    ];
  }
}

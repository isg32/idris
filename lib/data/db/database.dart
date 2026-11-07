import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// A YouTube playlist copied into Idris.
class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get ytId => text().unique()();
  TextColumn get title => text()();
  TextColumn get channel => text().withDefault(const Constant(''))();
  DateTimeColumn get importedAt => dateTime()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  /// "Available offline": every track is pre-cached and kept.
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
}

/// A YouTube video, shared by every playlist it is in.
class Tracks extends Table {
  TextColumn get videoId => text()();
  TextColumn get title => text()();
  TextColumn get channel => text().withDefault(const Constant(''))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();

  /// Pinned on its own (long-press → Pin offline).
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {videoId};
}

/// Which videos a playlist holds, in YouTube's order.
class PlaylistTracks extends Table {
  IntColumn get playlistId =>
      integer().references(Playlists, #id, onDelete: KeyAction.cascade)();
  TextColumn get videoId => text().references(Tracks, #videoId)();
  IntColumn get position => integer()();

  /// When Idris first saw it in the playlist ("Recently added").
  DateTimeColumn get firstSeenAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {playlistId, videoId};
}

/// An audio file in the cache (complete, or partly downloaded).
class CacheEntries extends Table {
  TextColumn get videoId => text()();
  TextColumn get path => text()();
  IntColumn get bytes => integer().withDefault(const Constant(0))();
  IntColumn get totalBytes => integer().nullable()();
  IntColumn get kbps => integer().withDefault(const Constant(0))();
  TextColumn get mime => text().withDefault(const Constant('audio/mp4'))();
  BoolColumn get complete => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastPlayedAt => dateTime().nullable()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {videoId};
}

/// Each time a track started playing ("Recently played").
class Plays extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get videoId => text()();
  DateTimeColumn get playedAt => dateTime()();
}

/// Settings, as key/value text.
class Prefs extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(
  tables: [Playlists, Tracks, PlaylistTracks, CacheEntries, Plays, Prefs],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'idris'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

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

  /// A cover the user chose (a file in `covers/`), instead of the mosaic.
  TextColumn get coverPath => text().nullable()();
}

/// A YouTube video, shared by every playlist it is in.
class Tracks extends Table {
  TextColumn get videoId => text()();
  TextColumn get title => text()();
  TextColumn get channel => text().withDefault(const Constant(''))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();

  /// Pinned on its own (long-press → Pin offline).
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();

  /// A cover the user chose (a file in `covers/`), instead of YouTube's.
  TextColumn get coverPath => text().nullable()();

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

/// A folder on the phone the user chose for "On this phone" (a Storage
/// Access Framework tree, readable for good once chosen).
class LocalFolders extends Table {
  TextColumn get uri => text()();
  TextColumn get name => text()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {uri};
}

/// An audio file in a [LocalFolders] folder, as the [Tracks] row with the
/// same `videoId` (`local:…`), which holds its title, artist and length.
class LocalFiles extends Table {
  TextColumn get videoId => text()();
  TextColumn get uri => text().unique()();
  TextColumn get folderUri => text()();

  /// When the file last changed, so a rescan reads only what's new.
  IntColumn get modifiedMs => integer().withDefault(const Constant(0))();
  IntColumn get bytes => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {videoId};
}

/// Settings, as key/value text.
class Prefs extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    Playlists,
    Tracks,
    PlaylistTracks,
    CacheEntries,
    Plays,
    Prefs,
    LocalFolders,
    LocalFiles,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'idris'));

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Covers the user chose.
        await m.addColumn(playlists, playlists.coverPath);
        await m.addColumn(tracks, tracks.coverPath);
      }
      if (from < 3) {
        // Music from folders on the phone.
        await m.createTable(localFolders);
        await m.createTable(localFiles);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

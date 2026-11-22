import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idris/data/db/database.dart';
import 'package:idris/data/library.dart';
import 'package:idris/platform/covers.dart';
import 'package:idris/platform/youtube.dart';

YtPlaylist pl(List<String> ids) => YtPlaylist(
  id: 'PLtest',
  title: 'Daily chants',
  channel: 'Me',
  videos: [
    for (final id in ids)
      YtVideo(
        id: id,
        title: 'Track $id',
        channel: 'Channel',
        duration: const Duration(minutes: 4),
      ),
  ],
);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('idris_covers_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a version 1 library opens with its playlists and tracks', () async {
    // The tables as 1.2.0 made them, before covers.
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(
            'CREATE TABLE playlists (id INTEGER NOT NULL PRIMARY KEY '
            'AUTOINCREMENT, yt_id TEXT NOT NULL UNIQUE, title TEXT NOT NULL, '
            "channel TEXT NOT NULL DEFAULT '', imported_at INTEGER NOT NULL, "
            'last_synced_at INTEGER NULL, pinned INTEGER NOT NULL DEFAULT 0)',
          );
          raw.execute(
            'CREATE TABLE tracks (video_id TEXT NOT NULL, title TEXT NOT NULL, '
            "channel TEXT NOT NULL DEFAULT '', duration_ms INTEGER NOT NULL "
            'DEFAULT 0, pinned INTEGER NOT NULL DEFAULT 0, '
            'PRIMARY KEY (video_id))',
          );
          raw.execute(
            "INSERT INTO playlists (yt_id, title, imported_at) VALUES ('PLx', "
            "'Old one', 0)",
          );
          raw.execute(
            "INSERT INTO tracks (video_id, title) VALUES ('a', 'Old track')",
          );
          raw.execute('PRAGMA user_version = 1');
        },
      ),
    );
    addTearDown(db.close);
    final library = Library(db);
    final p = (await library.allPlaylists()).single;
    expect(p.title, 'Old one');
    expect(p.coverPath, isNull);
    expect((await library.track('a'))!.coverPath, isNull);
  });

  test('covers are set, survive a sync, and reset', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final library = Library(db);
    final id = await library.importPlaylist(pl(['a', 'b']));

    await library.setTrackCover('a', '/covers/a.jpg');
    await library.setPlaylistCover(id, '/covers/p.jpg');
    // A sync rewrites the tracks from YouTube: the chosen cover stays.
    await library.syncPlaylist(id, pl(['a', 'b']));
    expect((await library.track('a'))!.coverPath, '/covers/a.jpg');
    expect(await library.coverPaths(), {'/covers/a.jpg', '/covers/p.jpg'});

    await library.setTrackCover('a', null);
    expect((await library.track('a'))!.coverPath, isNull);
    expect(await library.coverPaths(), {'/covers/p.jpg'});
  });

  test('a chosen image is copied in, and unused copies are tidied', () async {
    final covers = Covers(dir: Directory('${tmp.path}/covers'));
    final picked = File('${tmp.path}/photo.PNG')..writeAsBytesSync([1, 2, 3]);

    final kept = await covers.keep(picked.path, 'track-a/b');
    expect(File(kept).readAsBytesSync(), [1, 2, 3]);
    expect(kept, endsWith('.png'));
    expect(kept, contains('track-a_b-'));
    // The original can go; the copy stays.
    picked.deleteSync();
    expect(File(kept).existsSync(), isTrue);

    final other = await covers.keep(kept, 'playlist-1');
    await covers.tidy({other});
    expect(File(kept).existsSync(), isFalse);
    expect(File(other).existsSync(), isTrue);
  });
}

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idris/data/db/database.dart';
import 'package:idris/data/library.dart';
import 'package:idris/platform/youtube.dart';

YtVideo v(String id) => YtVideo(
  id: id,
  title: 'Track $id',
  channel: 'Channel',
  duration: const Duration(minutes: 4),
);

YtPlaylist pl(List<String> ids, {String title = 'Daily chants'}) => YtPlaylist(
  id: 'PLtest',
  title: title,
  channel: 'Me',
  videos: [for (final id in ids) v(id)],
);

void main() {
  late AppDatabase db;
  late Library library;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    library = Library(db);
  });
  tearDown(() => db.close());

  test('import, then a sync adds new videos and drops removed ones', () async {
    final day1 = DateTime(2026, 11, 1);
    final id = await library.importPlaylist(pl(['a', 'b', 'c']), now: day1);
    expect(
      (await library.playlistTracks(id)).map((t) => t.videoId),
      ['a', 'b', 'c'],
    );

    final r = await library.syncPlaylist(
      id,
      pl(['b', 'c', 'd']),
      now: day1.add(const Duration(days: 2)),
    );
    expect(r.added, 1);
    expect(r.removed, 1);
    expect(
      (await library.playlistTracks(id)).map((t) => t.videoId),
      ['b', 'c', 'd'],
    );

    // The new one leads Recently added, marked new; first imports aren't.
    final added = await library.watchRecentlyAdded().first;
    expect(added.first.track.videoId, 'd');
    expect(added.first.isNew, isTrue);
    expect(added.where((x) => x.track.videoId == 'b').single.isNew, isFalse);

    // The removed video's track row is gone (no other playlist has it).
    expect(await library.track('a'), isNull);
  });

  test('importing the same playlist again syncs it', () async {
    final id1 = await library.importPlaylist(pl(['a']));
    final id2 = await library.importPlaylist(pl(['a', 'b']));
    expect(id2, id1);
    expect(await library.playlistTracks(id1), hasLength(2));
  });

  test('a rename survives a sync', () async {
    final id = await library.importPlaylist(pl(['a']));
    await library.renamePlaylist(id, 'Mine');
    await library.syncPlaylist(id, pl(['a'], title: 'YouTube name'));
    expect((await library.watchPlaylist(id).first)!.title, 'Mine');
  });

  test('pinned IDs come from pinned playlists and pinned tracks', () async {
    final id = await library.importPlaylist(pl(['a', 'b']));
    expect(await library.pinnedVideoIds(), isEmpty);
    await library.setTrackPinned('a', true);
    expect(await library.pinnedVideoIds(), {'a'});
    await library.setPlaylistPinned(id, true);
    expect(await library.pinnedVideoIds(), {'a', 'b'});
  });

  test('playlist summaries count cached tracks', () async {
    await library.importPlaylist(pl(['a', 'b']));
    await library.putCache(
      CacheEntriesCompanion.insert(
        videoId: 'a',
        path: '/a',
        bytes: const Value(100),
        complete: const Value(true),
        cachedAt: DateTime(2026),
      ),
    );
    final s = (await library.watchPlaylists().first).single;
    expect(s.trackCount, 2);
    expect(s.cachedCount, 1);
    expect(s.total, const Duration(minutes: 8));
  });

  test('recently played lists each track once, newest first', () async {
    await library.importPlaylist(pl(['a', 'b']));
    await library.recordPlay('a', at: DateTime(2026, 11, 1, 9));
    await library.recordPlay('b', at: DateTime(2026, 11, 1, 10));
    await library.recordPlay('a', at: DateTime(2026, 11, 1, 11));
    final r = await library.watchRecentlyPlayed().first;
    expect(r.map((x) => x.track.videoId), ['a', 'b']);
    expect(r.first.playlistTitle, 'Daily chants');
  });

  test('export and parse round-trip', () async {
    final id = await library.importPlaylist(pl(['a']));
    await library.setPlaylistPinned(id, true);
    final parsed = Library.parseExport(await library.exportJson());
    expect(parsed.single.id, 'PLtest');
    expect(parsed.single.pinned, isTrue);
    expect(
      () => Library.parseExport('{"app":"other"}'),
      throwsFormatException,
    );
  });

  test('settings default, then follow prefs', () async {
    expect((await library.settings()).cacheLimitGb, 5);
    await library.setPref('cacheLimitGb', '10');
    expect((await library.settings()).cacheLimitGb, 10);
  });
}

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idris/data/db/database.dart';
import 'package:idris/data/library.dart';
import 'package:idris/platform/local_music.dart';
import 'package:idris/platform/youtube.dart';

/// The phone, pretended: one folder whose files can change.
class FakePhone implements LocalMusicPlatform {
  List<FoundFile> files = [];
  final tagged = <String>[];
  final forgotten = <String>[];

  @override
  Future<PickedFolder?> pickFolder() async =>
      const PickedFolder('tree:/Music', 'Music');

  @override
  Future<List<FoundFile>> list(String folderUri) async => files;

  @override
  Future<List<FileTags>> tags(List<String> uris) async {
    tagged.addAll(uris);
    return [
      for (final u in uris)
        u.endsWith('untagged.mp3')
            ? const FileTags()
            : FileTags(title: 'Song $u', artist: 'Artist', durationMs: 1000),
    ];
  }

  @override
  Future<bool> art(String uri, String outPath) async => false;

  @override
  Future<void> forget(String folderUri) async => forgotten.add(folderUri);
}

FoundFile file(String name, {int modified = 1}) =>
    FoundFile(uri: 'doc:/$name', name: name, modifiedMs: modified);

void main() {
  late AppDatabase db;
  late Library library;
  late FakePhone phone;
  late LocalMusic music;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    library = Library(db);
    phone = FakePhone();
    music = LocalMusic(library, phone);
  });
  tearDown(() => db.close());

  test('a chosen folder\'s files become songs, named by their tags', () async {
    phone.files = [file('a.mp3'), file('untagged.mp3')];
    expect(await music.addFolder(), 2);

    final tracks = await music.tracks();
    expect(tracks.map((t) => t.title), ['Song doc:/a.mp3', 'untagged']);
    expect(tracks.first.channel, 'Artist');
    expect(tracks.every((t) => isLocal(t.videoId)), isTrue);
    expect(await music.uriOf(localId('doc:/a.mp3')), 'doc:/a.mp3');
  });

  test(
    'a rescan reads only new and changed files, and drops gone ones',
    () async {
      phone.files = [file('a.mp3'), file('b.mp3'), file('c.mp3')];
      await music.addFolder();
      phone.tagged.clear();

      phone.files = [
        file('a.mp3'), // unchanged
        file('b.mp3', modified: 2), // changed
        file('d.mp3'), // new; c.mp3 is gone
      ];
      expect(await music.scanAll(), 1);
      expect(phone.tagged, ['doc:/b.mp3', 'doc:/d.mp3']);
      expect((await music.tracks()).map((t) => t.title), [
        'Song doc:/a.mp3',
        'Song doc:/b.mp3',
        'Song doc:/d.mp3',
      ]);
      expect(await library.track(localId('doc:/c.mp3')), isNull);
    },
  );

  test('removing a folder drops its songs, not YouTube\'s', () async {
    await library.importPlaylist(
      const YtPlaylist(
        id: 'PL',
        title: 'Chants',
        channel: '',
        videos: [
          YtVideo(id: 'yt1', title: 'Om', channel: '', duration: Duration.zero),
        ],
      ),
    );
    phone.files = [file('a.mp3')];
    await music.addFolder();

    // A YouTube sync tidies orphans: local songs aren't orphans.
    await library.dropOrphans();
    expect(await music.tracks(), hasLength(1));

    await music.removeFolder('tree:/Music');
    expect(await music.tracks(), isEmpty);
    expect(await library.track('yt1'), isNotNull);
    expect(phone.forgotten, ['tree:/Music']);
  });
}

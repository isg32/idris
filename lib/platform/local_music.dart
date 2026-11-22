import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../data/db/database.dart';
import '../data/library.dart';

/// Tracks from folders on the phone have IDs like `local:3f2a…`, so they
/// can share the [Tracks] table (and the player, queue and covers) with
/// YouTube's.
const localPrefix = 'local:';

bool isLocal(String videoId) => videoId.startsWith(localPrefix);

/// What the local list is called: "On this phone", or on a PC "On this
/// computer".
String get localLabel =>
    Platform.isLinux ? 'On this computer' : 'On this phone';

/// [localLabel] in one word, for a tablet's rail.
String get localShortLabel => Platform.isLinux ? 'Computer' : 'Phone';

/// The ID for the file at [uri]: stable, so plays and covers stay with it.
String localId(String uri) =>
    '$localPrefix${sha1.convert(utf8.encode(uri)).toString().substring(0, 20)}';

/// A folder the user chose.
class PickedFolder {
  const PickedFolder(this.uri, this.name);
  final String uri;
  final String name;
}

/// An audio file in a chosen folder.
class FoundFile {
  const FoundFile({
    required this.uri,
    required this.name,
    this.bytes = 0,
    this.modifiedMs = 0,
  });

  final String uri;

  /// The file name, `Om Namah Shivaya.mp3`.
  final String name;
  final int bytes;
  final int modifiedMs;
}

/// What a file says about itself (blank when it says nothing).
class FileTags {
  const FileTags({this.title = '', this.artist = '', this.durationMs = 0});
  final String title;
  final String artist;
  final int durationMs;
}

/// Reading music from folders on the phone (Storage Access Framework on
/// Android; see LocalMusic.kt).
abstract interface class LocalMusicPlatform {
  /// Lets the user choose a folder; null if they don't.
  Future<PickedFolder?> pickFolder();

  /// Every audio file in [folderUri] and the folders inside it.
  Future<List<FoundFile>> list(String folderUri);

  /// Tags of each file in [uris], in the same order.
  Future<List<FileTags>> tags(List<String> uris);

  /// Writes the file's embedded picture to [outPath]; false if it has none.
  Future<bool> art(String uri, String outPath);

  /// Gives back access to [folderUri].
  Future<void> forget(String folderUri);
}

/// [LocalMusicPlatform] over the `idris/local` channel.
class ChannelLocalMusic implements LocalMusicPlatform {
  static const _channel = MethodChannel('idris/local');

  @override
  Future<PickedFolder?> pickFolder() async {
    final m = await _channel.invokeMapMethod<String, Object?>('pickFolder');
    if (m == null) return null;
    return PickedFolder(m['uri']! as String, (m['name'] as String?) ?? '');
  }

  @override
  Future<List<FoundFile>> list(String folderUri) async {
    final rows =
        await _channel.invokeListMethod<Object?>('list', {'uri': folderUri}) ??
        const [];
    return [
      for (final r in rows.cast<Map<Object?, Object?>>())
        FoundFile(
          uri: r['uri']! as String,
          name: (r['name'] as String?) ?? '',
          bytes: (r['bytes'] as num?)?.toInt() ?? 0,
          modifiedMs: (r['modified'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  @override
  Future<List<FileTags>> tags(List<String> uris) async {
    final rows =
        await _channel.invokeListMethod<Object?>('tags', {'uris': uris}) ??
        const [];
    return [
      for (final r in rows.cast<Map<Object?, Object?>>())
        FileTags(
          title: (r['title'] as String?) ?? '',
          artist: (r['artist'] as String?) ?? '',
          durationMs: (r['duration'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  @override
  Future<bool> art(String uri, String outPath) async =>
      await _channel.invokeMethod<bool>('art', {'uri': uri, 'out': outPath}) ??
      false;

  @override
  Future<void> forget(String folderUri) =>
      _channel.invokeMethod<void>('forget', {'uri': folderUri});
}

/// [LocalMusicPlatform] on Linux: a folder dialog, the files read straight
/// from disk, and tags read in Dart (audio_metadata_reader). A "URI" here
/// is the file's path.
class DiskLocalMusic implements LocalMusicPlatform {
  static const _audio = {
    '.mp3', '.m4a', '.aac', '.flac', '.ogg', '.oga', '.opus', '.wav', //
    '.wma', '.alac', '.aiff', '.aif', '.mka', '.webm',
  };

  @override
  Future<PickedFolder?> pickFolder() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose a folder of music',
    );
    if (path == null) return null;
    return PickedFolder(path, p.basename(path));
  }

  @override
  Future<List<FoundFile>> list(String folderUri) async {
    final out = <FoundFile>[];
    await for (final e in Directory(
      folderUri,
    ).list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      // Hidden files and folders (".thumbnails") hold no music.
      if (p
          .split(p.relative(e.path, from: folderUri))
          .any((part) => part.startsWith('.'))) {
        continue;
      }
      if (!_audio.contains(p.extension(name).toLowerCase())) continue;
      final stat = await e.stat();
      out.add(
        FoundFile(
          uri: e.path,
          name: name,
          bytes: stat.size,
          modifiedMs: stat.modified.millisecondsSinceEpoch,
        ),
      );
    }
    return out;
  }

  @override
  Future<List<FileTags>> tags(List<String> uris) => compute(_readTags, uris);

  @override
  Future<bool> art(String uri, String outPath) async {
    final bytes = await compute(_readArt, uri);
    if (bytes == null) return false;
    final tmp = File('$outPath.part');
    await tmp.writeAsBytes(bytes);
    await tmp.rename(outPath);
    return true;
  }

  @override
  Future<void> forget(String folderUri) async {}
}

List<FileTags> _readTags(List<String> paths) => [
  for (final path in paths) _tagsOf(path),
];

FileTags _tagsOf(String path) {
  try {
    final m = readMetadata(File(path));
    return FileTags(
      title: m.title ?? '',
      artist: m.artist ?? '',
      durationMs: m.duration?.inMilliseconds ?? 0,
    );
  } on Object {
    return const FileTags(); // unreadable tags: the file name stands in
  }
}

Uint8List? _readArt(String path) {
  try {
    final pictures = readMetadata(File(path), getImage: true).pictures;
    return pictures.isEmpty ? null : pictures.first.bytes;
  } on Object {
    return null;
  }
}

/// "On this phone": the folders the user chose and the music in them.
class LocalMusic {
  LocalMusic(this.library, this.platform);

  final Library library;
  final LocalMusicPlatform platform;
  AppDatabase get _db => library.db;

  Stream<List<LocalFolder>> watchFolders() => (_db.select(
    _db.localFolders,
  )..orderBy([(f) => OrderingTerm.asc(f.name)])).watch();

  /// Every local track, by title.
  Stream<List<Track>> watchTracks() {
    final q = _db.select(_db.tracks).join([
      innerJoin(
        _db.localFiles,
        _db.localFiles.videoId.equalsExp(_db.tracks.videoId),
      ),
    ])..orderBy([OrderingTerm.asc(_db.tracks.title.collate(Collate.noCase))]);
    return q.watch().map(
      (rows) => [for (final r in rows) r.readTable(_db.tracks)],
    );
  }

  Future<List<Track>> tracks() => watchTracks().first;

  /// Songs in each folder, by folder URI.
  Stream<Map<String, int>> watchCounts() {
    final count = _db.localFiles.videoId.count();
    final q = _db.selectOnly(_db.localFiles)
      ..addColumns([_db.localFiles.folderUri, count])
      ..groupBy([_db.localFiles.folderUri]);
    return q.watch().map(
      (rows) => {
        for (final r in rows)
          r.read(_db.localFiles.folderUri)!: r.read(count) ?? 0,
      },
    );
  }

  /// Where the file for [videoId] is, to play it.
  Future<String?> uriOf(String videoId) async => (await (_db.select(
    _db.localFiles,
  )..where((f) => f.videoId.equals(videoId))).getSingleOrNull())?.uri;

  /// Lets the user choose a folder, then reads it. Returns the songs added
  /// (null if no folder was chosen).
  Future<int?> addFolder() async {
    final picked = await platform.pickFolder();
    if (picked == null) return null;
    await _db
        .into(_db.localFolders)
        .insertOnConflictUpdate(
          LocalFoldersCompanion.insert(
            uri: picked.uri,
            name: picked.name.isEmpty ? 'Music' : picked.name,
            addedAt: DateTime.now(),
          ),
        );
    return scan(picked.uri);
  }

  /// Takes [folderUri]'s songs out of Idris (the files stay on the phone).
  Future<void> removeFolder(String folderUri) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.localFiles,
      )..where((f) => f.folderUri.equals(folderUri))).go();
      await (_db.delete(
        _db.localFolders,
      )..where((f) => f.uri.equals(folderUri))).go();
    });
    await library.dropOrphans();
    try {
      await platform.forget(folderUri);
    } on Object {
      // Access already gone.
    }
  }

  /// Reads every chosen folder again. Returns the songs added.
  Future<int> scanAll() async {
    var added = 0;
    for (final f in await _db.select(_db.localFolders).get()) {
      try {
        added += await scan(f.uri);
      } on Object {
        // The folder is gone or unreadable: its songs stay until removed.
      }
    }
    return added;
  }

  /// Brings [folderUri]'s songs up to date: new and changed files are read
  /// (in batches, so they show as they come), and gone ones dropped.
  /// Returns the songs added.
  Future<int> scan(String folderUri) async {
    final found = await platform.list(folderUri);
    final known = {
      for (final f in await (_db.select(
        _db.localFiles,
      )..where((f) => f.folderUri.equals(folderUri))).get())
        f.uri: f,
    };
    final fresh = [
      for (final f in found)
        if (known[f.uri]?.modifiedMs != f.modifiedMs) f,
    ];
    final added = fresh.where((f) => !known.containsKey(f.uri)).length;
    const batch = 25;
    for (var i = 0; i < fresh.length; i += batch) {
      final part = fresh.sublist(
        i,
        i + batch > fresh.length ? fresh.length : i + batch,
      );
      final tags = await platform.tags([for (final f in part) f.uri]);
      await _db.batch((b) {
        for (final (j, f) in part.indexed) {
          final t = j < tags.length ? tags[j] : const FileTags();
          final id = localId(f.uri);
          final title = t.title.trim().isNotEmpty
              ? t.title.trim()
              : _withoutExtension(f.name);
          b.insert(
            _db.tracks,
            TracksCompanion.insert(
              videoId: id,
              title: title,
              channel: Value(t.artist.trim()),
              durationMs: Value(t.durationMs),
            ),
            onConflict: DoUpdate(
              (_) => TracksCompanion(
                title: Value(title),
                channel: Value(t.artist.trim()),
                durationMs: Value(t.durationMs),
              ),
            ),
          );
          b.insert(
            _db.localFiles,
            LocalFilesCompanion.insert(
              videoId: id,
              uri: f.uri,
              folderUri: folderUri,
              modifiedMs: Value(f.modifiedMs),
              bytes: Value(f.bytes),
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });
    }
    final gone = known.keys.toSet().difference({for (final f in found) f.uri});
    if (gone.isNotEmpty) {
      await (_db.delete(_db.localFiles)..where((f) => f.uri.isIn(gone))).go();
      await library.dropOrphans();
    }
    return added;
  }

  static String _withoutExtension(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}

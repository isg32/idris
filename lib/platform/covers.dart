import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Covers the user chose for tracks and playlists: copies of their images,
/// kept in `<appSupport>/covers`, so they stay when the original is moved
/// or deleted.
class Covers {
  Covers({Directory? dir}) : _override = dir;

  final Directory? _override;
  Directory? _dir;

  Future<Directory> get dir async {
    final d = _dir ??=
        _override ??
        Directory(
          p.join((await getApplicationSupportDirectory()).path, 'covers'),
        );
    if (!d.existsSync()) await d.create(recursive: true);
    return d;
  }

  /// Copies the image at [source] in as [name]'s cover and returns where it
  /// is. Each copy gets a new file name, so a changed cover shows at once
  /// (images are cached by path).
  Future<String> keep(String source, String name) async {
    final ext = p.extension(source).toLowerCase();
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final to = p.join(
      (await dir).path,
      '$safe-$stamp${ext.isEmpty ? '.jpg' : ext}',
    );
    await File(source).copy(to);
    return to;
  }

  /// Deletes covers no track or playlist uses any more.
  Future<void> tidy(Set<String> inUse) async {
    for (final f in (await dir).listSync().whereType<File>()) {
      if (!inUse.contains(f.path)) {
        try {
          f.deleteSync();
        } on Object {
          // Next time.
        }
      }
    }
  }
}

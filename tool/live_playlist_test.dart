// Live check against YouTube (not part of `flutter test`; run by hand):
//   flutter test tool/live_playlist_test.dart --dart-define=PLAYLISTS=<id>,<id>
import 'package:flutter_test/flutter_test.dart';
import 'package:idris/platform/youtube.dart';

void main() {
  const ids = String.fromEnvironment('PLAYLISTS');
  for (final id in ids.split(',').where((s) => s.isNotEmpty)) {
    test('reads $id', () async {
      final sw = Stopwatch()..start();
      final p = await fetchPlaylist(id);
      final noLength = p.videos.where((v) => v.duration == Duration.zero);
      // ignore: avoid_print
      print('${p.title} · ${p.channel}: ${p.videos.length} videos, '
          '${noLength.length} without a length, ${sw.elapsedMilliseconds} ms\n'
          '  first: ${p.videos.first.id} ${p.videos.first.duration} '
          '${p.videos.first.title} · ${p.videos.first.channel}');
      expect(p.videos, isNotEmpty);
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idris/data/db/database.dart';
import 'package:idris/data/library.dart';
import 'package:idris/platform/cache_manager.dart';
import 'package:idris/platform/quality.dart';
import 'package:idris/platform/youtube.dart';

/// A slow range-only server: each request waits a little, so a download is
/// still running when the next track opens.
Future<HttpServer> _serve(Uint8List data) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final m = RegExp(r'bytes=(\d+)-(\d*)')
        .firstMatch(req.headers.value(HttpHeaders.rangeHeader) ?? '');
    final start = int.parse(m!.group(1)!);
    final end = m.group(2)!.isEmpty
        ? data.length - 1
        : int.parse(m.group(2)!).clamp(0, data.length - 1);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    req.response
      ..statusCode = HttpStatus.partialContent
      ..headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/${data.length}',
      )
      ..add(data.sublist(start, end + 1));
    await req.response.close();
  });
  return server;
}

void main() {
  late Directory tmp;
  late HttpServer server;
  late CacheManager cache;
  late AppDatabase db;
  // 4 MB: four 1 MB requests, so it's mid-way when the next track opens.
  final data = Uint8List.fromList(List.generate(4 << 20, (i) => i % 251));

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('idris_cm_');
    server = await _serve(data);
    db = AppDatabase(NativeDatabase.memory());
    cache = CacheManager(
      Library(db),
      dir: tmp,
      connectivity: const Stream.empty(),
      checkConnectivity: () async => [ConnectivityResult.wifi],
      resolve: (id, quality, {from = 0, resolvers}) async => (
        ResolvedAudio(
          url: Uri.parse('http://127.0.0.1:${server.port}/$id'),
          kbps: 128,
          mime: 'audio/mp4',
          bytes: data.length,
        ),
        0,
      ),
    );
  });

  tearDown(() async {
    cache.dispose();
    await server.close(force: true);
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test('moving to another track stops the last one caching', () async {
    final a = await cache.open('a', AudioQuality.best);
    expect(a.cached, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final partA = File('${tmp.path}/a.m4a.part');
    expect(partA.existsSync(), isTrue);

    await cache.open('b', AudioQuality.best);
    final stoppedAt = partA.lengthSync();
    await Future<void>.delayed(const Duration(milliseconds: 600));

    // A's download stopped (its .part kept, to resume), B's runs alone.
    expect(partA.lengthSync(), stoppedAt);
    expect(stoppedAt, lessThan(data.length));
    expect(cache.progress.value.keys, isNot(contains('a')));
    expect((await Library(db).cacheEntry('a'))!.complete, isFalse);
    expect(File('${tmp.path}/b.m4a.part').existsSync(), isTrue);
  });

  test('reopening the same track keeps its download', () async {
    await cache.open('a', AudioQuality.best);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await cache.open('a', AudioQuality.best);
    await Future<void>.delayed(const Duration(seconds: 2));
    expect((await Library(db).cacheEntry('a'))!.complete, isTrue);
    expect(File('${tmp.path}/a.m4a').lengthSync(), data.length);
  });
}

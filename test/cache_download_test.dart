import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:idris/platform/cache_download.dart';

/// A local server that only answers range requests, like YouTube's.
Future<(HttpServer, List<String>)> _serve(Uint8List data) async {
  final ranges = <String>[];
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final range = req.headers.value(HttpHeaders.rangeHeader);
    ranges.add(range ?? 'none');
    final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range ?? '');
    if (m == null) {
      req.response.statusCode = HttpStatus.forbidden;
      await req.response.close();
      return;
    }
    final start = int.parse(m.group(1)!);
    final end = m.group(2)!.isEmpty
        ? data.length - 1
        : int.parse(m.group(2)!).clamp(0, data.length - 1);
    req.response
      ..statusCode = HttpStatus.partialContent
      ..headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/${data.length}',
      )
      ..add(data.sublist(start, end + 1));
    await req.response.close();
  });
  return (server, ranges);
}

void main() {
  late Directory tmp;
  final data = Uint8List.fromList(List.generate(250000, (i) => i % 251));

  setUp(() => tmp = Directory.systemTemp.createTempSync('idris_cache_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('downloads in range chunks into the file', () async {
    final (server, ranges) = await _serve(data);
    final url = Uri.parse('http://127.0.0.1:${server.port}/a');
    final total = await CacheDownload.fetchLength(url);
    expect(total, data.length);

    final d = CacheDownload(
      videoId: 'a',
      url: url,
      partFile: File('${tmp.path}/a.m4a.part'),
      total: total,
      mime: 'audio/mp4',
      chunk: 64 * 1024,
    )..start();
    await d.done;

    expect(d.isComplete, isTrue);
    expect(d.partFile.readAsBytesSync(), data);
    // 0-0 length probe, then four 64 KB chunks.
    expect(ranges.where((r) => r != 'bytes=0-0'), hasLength(4));
    await server.close(force: true);
  });

  test('a reader gets the bytes while they download', () async {
    final (server, _) = await _serve(data);
    final url = Uri.parse('http://127.0.0.1:${server.port}/b');
    final d = CacheDownload(
      videoId: 'b',
      url: url,
      partFile: File('${tmp.path}/b.part'),
      total: data.length,
      mime: 'audio/mp4',
      chunk: 32 * 1024,
    );
    final source = CachingAudioSource(d);
    final res = await source.request(1000, 200000);
    final got = await res.stream.expand((b) => b).toList();
    expect(res.offset, 1000);
    expect(res.sourceLength, data.length);
    expect(got, data.sublist(1000, 200000));
    await d.done;
    await server.close(force: true);
  });

  test('a seek far ahead reads from the network directly', () async {
    final (server, ranges) = await _serve(data);
    final url = Uri.parse('http://127.0.0.1:${server.port}/c');
    final d = CacheDownload(
      videoId: 'c',
      url: url,
      partFile: File('${tmp.path}/c.part'),
      total: data.length,
      mime: 'audio/mp4',
      chunk: 16 * 1024,
    );
    final got = await d.read(200000, 210000).expand((b) => b).toList();
    expect(got, data.sublist(200000, 210000));
    expect(ranges, contains('bytes=200000-209999'));
    await server.close(force: true);
  });

  test('a half-downloaded file resumes where it stopped', () async {
    final (server, ranges) = await _serve(data);
    final url = Uri.parse('http://127.0.0.1:${server.port}/d');
    final part = File('${tmp.path}/d.part')
      ..writeAsBytesSync(data.sublist(0, 100000));
    final d = CacheDownload(
      videoId: 'd',
      url: url,
      partFile: part,
      total: data.length,
      mime: 'audio/mp4',
      chunk: 200000,
    );
    expect(d.written, 100000);
    d.start();
    await d.done;
    expect(part.readAsBytesSync(), data);
    expect(ranges.first, 'bytes=100000-249999');
    await server.close(force: true);
  });

  test('a refused stream fails the download', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      req.response.statusCode = HttpStatus.forbidden;
      await req.response.close();
    });
    final d = CacheDownload(
      videoId: 'e',
      url: Uri.parse('http://127.0.0.1:${server.port}/e'),
      partFile: File('${tmp.path}/e.part'),
      total: 1000,
      mime: 'audio/mp4',
    )..start();
    await expectLater(d.done, throwsA(isA<HttpException>()));
    await server.close(force: true);
  });
}

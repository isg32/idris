import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'net.dart';

/// Downloads one audio stream into a file, in order, in small range
/// requests, while letting playback read from it.
///
/// This is the "cache while it plays" trick: the bytes the player asks for
/// come from the file as soon as they're written, so a track played once is
/// on the phone for good. YouTube slows down big single requests, so the
/// file is fetched [chunk] bytes at a time, as NewPipe and yt-dlp do.
/// YouTube refuses (403) any request for more than 1 MB of a stream, so
/// [chunk] must stay at or under that; it's what YouTube's own players ask
/// for. A file left half-downloaded (`.part`) is resumed, not restarted.
class CacheDownload {
  CacheDownload({
    required this.videoId,
    required this.url,
    required this.partFile,
    required this.total,
    required this.mime,
    this.chunk = maxChunk,
    HttpClient? client,
  }) : _client = client ?? _streams,
       written = partFile.existsSync() ? partFile.lengthSync() : 0;

  /// The most YouTube serves in one request.
  static const int maxChunk = 1024 * 1024;

  final String videoId;
  final Uri url;
  final File partFile;
  final int total;
  final String mime;
  final int chunk;
  final HttpClient _client;

  /// Bytes in [partFile] so far.
  int written;

  final StreamController<void> _changed = StreamController.broadcast();
  final Completer<void> _done = Completer();
  bool _cancelled = false;
  Object? _error;
  bool _started = false;

  double get progress => total == 0 ? 0 : written / total;
  bool get isComplete => written >= total;
  Object? get error => _error;

  /// Completes when every byte is written (or with the download's error).
  Future<void> get done => _done.future;

  /// Starts fetching (once). Never throws; see [done].
  void start() {
    if (_started) return;
    _started = true;
    unawaited(_run());
  }

  Future<void> _run() async {
    RandomAccessFile? out;
    try {
      await partFile.parent.create(recursive: true);
      out = await partFile.open(mode: FileMode.append);
      while (written < total && !_cancelled) {
        final end = math.min(written + chunk, total) - 1;
        final req = await _client.getUrl(url);
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=$written-$end');
        final res = await req.close();
        if (res.statusCode != HttpStatus.partialContent &&
            res.statusCode != HttpStatus.ok) {
          await res.drain<void>();
          throw HttpException(
            'HTTP ${res.statusCode} for bytes=$written-$end of $total',
            uri: url,
          );
        }
        // A server that ignores the range sends the whole file: skip to
        // where we are.
        var skip = res.statusCode == HttpStatus.ok ? written : 0;
        await for (final data in res) {
          if (_cancelled) break;
          var bytes = data;
          if (skip > 0) {
            if (bytes.length <= skip) {
              skip -= bytes.length;
              continue;
            }
            bytes = bytes.sublist(skip);
            skip = 0;
          }
          final room = total - written;
          if (bytes.length > room) bytes = bytes.sublist(0, room);
          await out.writeFrom(bytes);
          written += bytes.length;
          _changed.add(null);
          if (written >= total) break;
        }
      }
      await out.flush();
      if (!_done.isCompleted) {
        if (written >= total) {
          _done.complete();
        } else {
          _done.completeError(StateError('Download cancelled'));
        }
      }
    } on Object catch (e) {
      debugPrint('Cache download of $videoId stopped: $e');
      _error = e;
      if (!_done.isCompleted) _done.completeError(e);
    } finally {
      await out?.close();
      _changed.add(null);
    }
    unawaited(_done.future.catchError((Object _) {}));
  }

  /// Stops fetching; the `.part` file stays for next time.
  void cancel() {
    _cancelled = true;
    _changed.add(null);
  }

  /// Bytes [start] (inclusive) to [end] (exclusive), from the file as they
  /// arrive. A read far ahead of the download (a seek) goes straight to the
  /// network instead of waiting.
  Stream<List<int>> read(int start, int end) async* {
    end = math.min(end, total);
    if (start > written + chunk ~/ 2 && !isComplete) {
      yield* _direct(start, end);
      return;
    }
    var pos = start;
    RandomAccessFile? file;
    try {
      while (pos < end) {
        if (pos < written) {
          file ??= await partFile.open();
          await file.setPosition(pos);
          final n = math.min(math.min(written, end) - pos, 64 * 1024);
          final bytes = await file.read(n);
          if (bytes.isEmpty) continue;
          pos += bytes.length;
          yield bytes;
          continue;
        }
        if (_error != null) throw _error!;
        if (_cancelled) throw StateError('Download cancelled');
        // Wait for the next bytes.
        await _changed.stream.first.timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException('Stream stalled'),
        );
      }
    } finally {
      await file?.close();
    }
  }

  /// Bytes [start] to [end] from the network, in [chunk]-sized requests.
  Stream<List<int>> _direct(int start, int end) async* {
    for (var from = start; from < end; from += chunk) {
      final to = math.min(from + chunk, end) - 1;
      final req = await _client.getUrl(url);
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-$to');
      final res = await req.close();
      if (res.statusCode != HttpStatus.partialContent) {
        await res.drain<void>();
        throw HttpException('HTTP ${res.statusCode}', uri: url);
      }
      yield* res;
    }
  }

  /// Asks the server how big the stream is (when YouTube didn't say).
  static Future<int> fetchLength(Uri url, {HttpClient? client}) async {
    final c = client ?? _streams;
    final req = await c.getUrl(url);
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
    final res = await req.close();
    await res.drain<void>();
    final range = res.headers.value(HttpHeaders.contentRangeHeader);
    final total = range == null ? null : int.tryParse(range.split('/').last);
    if (total != null) return total;
    if (res.statusCode == HttpStatus.ok && res.contentLength > 0) {
      return res.contentLength;
    }
    throw HttpException('No length (HTTP ${res.statusCode})', uri: url);
  }
}

// StreamAudioSource is marked experimental, but it has been stable for
// years and is the supported way to serve bytes to the player.
// ignore_for_file: experimental_member_use

/// The client every audio download uses (see `net.dart`).
final HttpClient _streams = youtubeHttpClient();

/// Plays a [CacheDownload] through just_audio's local proxy: the player
/// reads the file while it's still being written.
class CachingAudioSource extends StreamAudioSource {
  CachingAudioSource(this.download, {super.tag});

  final CacheDownload download;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    download.start();
    final from = start ?? 0;
    final to = math.min(end ?? download.total, download.total);
    return StreamAudioResponse(
      sourceLength: download.total,
      contentLength: to - from,
      offset: from,
      stream: download.read(from, to),
      contentType: download.mime,
    );
  }
}

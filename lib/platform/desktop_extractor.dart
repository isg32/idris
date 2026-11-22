import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'net.dart';

/// NewPipe's extractor on Linux: the Java helper in linux/extractor (the
/// same library the Android app uses), started once and kept running, so
/// each track waits on YouTube and not on Java starting.
///
/// It speaks one JSON object per line (see Extractor.java). In the AppImage
/// it sits beside the app as `extractor/` with its own trimmed Java runtime;
/// a development build uses the system's `java` and the Gradle output.
class DesktopExtractor {
  DesktopExtractor._();

  static final instance = DesktopExtractor._();

  Process? _process;
  Future<Process>? _starting;
  final Map<int, Completer<Map<String, Object?>>> _waiting = {};
  int _next = 0;

  /// The stream for the YouTube video at [link], as a map with `url`,
  /// `mime`, `bitrate` (kbps) and `ms`; throws when there's none.
  Future<Map<String, Object?>> audio(String link, String quality) async {
    final process = await (_starting ??= _start());
    final n = ++_next;
    final reply = Completer<Map<String, Object?>>();
    _waiting[n] = reply;
    process.stdin.writeln(
      jsonEncode({'n': n, 'link': link, 'quality': quality}),
    );
    final m = await reply.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        _waiting.remove(n);
        throw TimeoutException('The extractor took too long');
      },
    );
    final error = m['error'];
    if (error != null) throw StateError('NewPipe: $error');
    return m;
  }

  Future<Process> _start() async {
    final (java, classpath) = _locate();
    // YouTube ties a stream link to the address that asked for it, so the
    // helper must leave by the route the download will (see net.dart).
    final v6 = await preferredFamily() == InternetAddressType.IPv6;
    final process = await Process.start(java, [
      '-Djava.net.preferIPv6Addresses=$v6',
      '-Djava.net.preferIPv4Stack=${!v6}',
      '-Xss2m',
      '-cp',
      classpath,
      'com.isg32.idris.Extractor',
    ]);
    _process = process;
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_reply);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((l) => debugPrint('extractor: $l'));
    unawaited(
      process.exitCode.then((code) {
        debugPrint('Extractor exited ($code)');
        if (identical(_process, process)) {
          _process = null;
          _starting = null; // the next request starts it again
          for (final w in _waiting.values) {
            w.completeError(StateError('The extractor stopped'));
          }
          _waiting.clear();
        }
      }),
    );
    return process;
  }

  void _reply(String line) {
    try {
      final m = (jsonDecode(line) as Map).cast<String, Object?>();
      _waiting.remove((m['n'] as num?)?.toInt())?.complete(m);
    } on Object {
      debugPrint('extractor: $line');
    }
  }

  /// The Java to run and its classpath: the AppImage's bundled runtime
  /// beside the app, else (developing) the system's and Gradle's output.
  static (String, String) _locate() {
    final here = p.dirname(Platform.resolvedExecutable);
    final bundled = p.join(here, 'extractor');
    if (Directory(bundled).existsSync()) {
      return (
        p.join(bundled, 'runtime', 'bin', 'java'),
        p.join(bundled, 'lib', '*'),
      );
    }
    final dev = p.join(
      Directory.current.path,
      'linux/extractor/build/install/idris-extractor/lib',
    );
    final home = Platform.environment['JAVA_HOME'];
    return (
      home == null ? 'java' : p.join(home, 'bin', 'java'),
      p.join(dev, '*'),
    );
  }

  void dispose() => _process?.kill();
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'appimage_updater.dart';
import 'updater_channel.dart';

/// Where each release's `update.json` is: the latest GitHub release of the
/// public repo (see .github/workflows/release.yml). A build can point
/// elsewhere with --dart-define=IDRIS_UPDATE_URL (a local test server).
const updateManifestUrl = String.fromEnvironment(
  'IDRIS_UPDATE_URL',
  defaultValue:
      'https://github.com/isg32/idris/releases/latest/download/update.json',
);

/// The releases page, for a phone that has to reinstall once by hand.
const releasesPageUrl = 'https://github.com/isg32/idris/releases/latest';

/// A newer Idris, for this phone's ABI.
class UpdateRelease {
  const UpdateRelease({
    required this.version,
    required this.notes,
    required this.url,
    required this.sha256,
    required this.size,
    required this.versionCode,
  });

  final String version;
  final List<String> notes;
  final String url;
  final String sha256;
  final int size;
  final int versionCode;

  /// The release in an `update.json` for [abi], or null when it has no APK
  /// for it (or isn't readable).
  static UpdateRelease? fromManifest(Map<String, Object?> j, String? abi) {
    final apks = j['apks'];
    if (apks is! Map) return null;
    // An Android phone of another ABI can fall back to arm64's APK; a PC
    // (linux-x86_64) takes only its own AppImage, never an APK.
    final linux = abi != null && abi.startsWith('linux');
    final apk = linux
        ? apks[abi]
        : apks[abi ?? 'arm64-v8a'] ?? apks['arm64-v8a'];
    if (apk is! Map) return null;
    final url = apk['url'], sha = apk['sha256'];
    final size = apk['size'], code = apk['versionCode'];
    if (url is! String || sha is! String || size is! num || code is! num) {
      return null;
    }
    return UpdateRelease(
      version: (j['version'] as String?) ?? '',
      notes: [
        for (final n in (j['notes'] as List?) ?? const [])
          if (n is String && n.trim().isNotEmpty) n.trim(),
      ],
      url: url,
      sha256: sha.toLowerCase(),
      size: size.toInt(),
      versionCode: code.toInt(),
    );
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'notes': notes,
    'url': url,
    'sha256': sha256,
    'size': size,
    'versionCode': versionCode,
  };

  static UpdateRelease? fromJson(Object? j) {
    if (j is! Map) return null;
    return UpdateRelease.fromManifest({
      'version': j['version'],
      'notes': j['notes'],
      'apks': {'any': j},
    }, 'any');
  }

  String get sizeLabel => megabytes(size);
}

String megabytes(int bytes) {
  final mb = bytes / (1024 * 1024);
  return mb >= 10 ? '${mb.round()} MB' : '${mb.toStringAsFixed(1)} MB';
}

/// Where an update is.
sealed class UpdateState {
  const UpdateState();

  /// The release it's about, if any.
  UpdateRelease? get release => null;
}

/// Not on this phone (tests, the desktop build).
class UpdateUnsupported extends UpdateState {
  const UpdateUnsupported();
}

class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

class UpdateChecking extends UpdateState {
  const UpdateChecking();
}

class UpdateUpToDate extends UpdateState {
  const UpdateUpToDate();
}

class UpdateAvailable extends UpdateState {
  const UpdateAvailable(this.release);
  @override
  final UpdateRelease release;
}

class UpdateDownloading extends UpdateState {
  const UpdateDownloading(this.release, this.received);
  @override
  final UpdateRelease release;
  final int received;

  double get progress =>
      release.size == 0 ? 0 : (received / release.size).clamp(0.0, 1.0);
}

/// Downloaded and checked; installing is one tap.
class UpdateReady extends UpdateState {
  const UpdateReady(this.release, this.path);
  @override
  final UpdateRelease release;
  final String path;
}

/// Android needs "Install unknown apps" allowed for Idris first.
class UpdateNeedsPermission extends UpdateState {
  const UpdateNeedsPermission(this.release, this.path);
  @override
  final UpdateRelease release;
  final String path;
}

/// Installed in place (the Linux AppImage replaced itself): it takes over
/// when Idris restarts.
class UpdateRestartNeeded extends UpdateState {
  const UpdateRestartNeeded(this.release);
  @override
  final UpdateRelease release;
}

class UpdateInstalling extends UpdateState {
  const UpdateInstalling(this.release, this.path, {this.confirming = false});
  @override
  final UpdateRelease release;
  final String path;

  /// Android's "Update Idris?" screen is up.
  final bool confirming;
}

class UpdateFailed extends UpdateState {
  const UpdateFailed(this.message, {this.release, this.reinstall = false});
  final String message;
  @override
  final UpdateRelease? release;

  /// This Idris can't be updated in place (signed differently): reinstall
  /// it once from GitHub.
  final bool reinstall;
}

/// The phone, the network and the files an [Updater] works with.
class UpdateDeps {
  const UpdateDeps({
    required this.platform,
    required this.client,
    required this.dir,
    this.now = DateTime.now,
  });

  final UpdatePlatform platform;
  final http.Client client;

  /// Where downloads and the updater's notes are kept.
  final Future<Directory> Function() dir;
  final DateTime Function() now;
}

/// The phone's [UpdateDeps]; null where Idris doesn't update itself.
final updateDepsProvider = Provider<UpdateDeps?>((ref) => null);

/// Over-the-air updates: checks GitHub for a newer Idris, downloads it
/// (resuming if the connection drops), checks it, and hands it to Android
/// to install.
final updaterProvider = NotifierProvider<Updater, UpdateState>(Updater.new);

/// The version whose card was closed on Home.
final dismissedUpdateProvider = NotifierProvider<DismissedUpdate, String?>(
  DismissedUpdate.new,
);

class DismissedUpdate extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? version) => state = version;
}

class Updater extends Notifier<UpdateState> {
  /// How often a check runs by itself (at launch and on coming back).
  static const every = Duration(hours: 6);

  UpdateDeps? _deps;
  Directory? _dir;
  _Saved _saved = const _Saved();
  StreamSubscription<InstallResult>? _results;
  bool _downloading = false;

  @override
  UpdateState build() {
    _deps = ref.read(updateDepsProvider);
    final deps = _deps;
    if (deps == null) return const UpdateUnsupported();
    _results = deps.platform.results.listen(_onResult);
    ref.onDispose(() => _results?.cancel());
    return const UpdateIdle();
  }

  bool get supported => _deps != null;

  /// Work that outlives the updater (a check finishing after Idris closed)
  /// just stops.
  @override
  set state(UpdateState value) {
    if (ref.mounted) super.state = value;
  }

  Future<Directory> _folder() async {
    final d = _dir ??= Directory('${(await _deps!.dir()).path}/updates');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  File _stateFile(Directory d) => File('${d.path}/state.json');

  Future<void> _load() async {
    final f = _stateFile(await _folder());
    try {
      if (f.existsSync()) {
        _saved = _Saved.fromJson(
          jsonDecode(await f.readAsString()) as Map<String, Object?>,
        );
      }
    } on Object {
      _saved = const _Saved();
    }
  }

  Future<void> _save() async {
    final f = _stateFile(await _folder());
    await f.writeAsString(jsonEncode(_saved.toJson()));
  }

  /// At launch: tidies old downloads, works out "What's new", and checks if
  /// it's time. Returns the notes to show once after an update, if any.
  Future<UpdateRelease?> start() async {
    if (!supported) return null;
    try {
      await _load();
      ref.read(dismissedUpdateProvider.notifier).set(_saved.dismissed);
      final me = await _deps!.platform.info();
      await _tidy(me.versionCode);
      UpdateRelease? whatsNew;
      final pending = _saved.installing;
      if (pending != null && pending.versionCode <= me.versionCode) {
        // The update that was being installed is in: say what's new, once.
        whatsNew = pending;
        _saved = _saved.copyWith(installing: null, clearInstalling: true);
        await _save();
      }
      unawaited(check());
      return whatsNew;
    } on Object {
      return null;
    }
  }

  /// Coming back to Idris: carries on an install that was waiting for
  /// "Install unknown apps", and checks if it's time.
  Future<void> resumed() async {
    if (!supported) return;
    final s = state;
    if (s is UpdateNeedsPermission) {
      try {
        if ((await _deps!.platform.info()).canInstall) {
          await install();
          return;
        }
      } on Object {
        // Try again on the next tap.
      }
    }
    if (s is UpdateInstalling && !s.confirming) return;
    await check();
  }

  /// Looks for a newer Idris. [manual] checks now, whatever the time, and
  /// says so when something goes wrong; otherwise it only runs every
  /// [every] and fails quietly.
  Future<void> check({bool manual = false}) async {
    if (!supported) return;
    final deps = _deps!;
    final s = state;
    // Don't interrupt a download or an install.
    if (s is UpdateDownloading || s is UpdateInstalling) return;
    // Installed already, waiting for a restart: nothing to look for.
    if (s is UpdateRestartNeeded) return;
    if (s is UpdateChecking) return;
    final last = _saved.checked;
    if (!manual && last != null && deps.now().difference(last) < every) {
      // Checked lately: show what that check found, without the network.
      if (s is UpdateIdle) await _showSaved();
      return;
    }
    final keep = s;
    if (manual || s is UpdateIdle || s is UpdateUpToDate) {
      state = const UpdateChecking();
    }
    try {
      final me = await deps.platform.info();
      final res = await deps.client
          .get(
            Uri.parse(updateManifestUrl),
            headers: {'cache-control': 'no-cache'},
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 404) {
        // No release yet.
        _saved = _saved.copyWith(checked: deps.now(), clearLatest: true);
        await _save();
        state = const UpdateUpToDate();
        return;
      }
      if (res.statusCode != 200) throw HttpException('${res.statusCode}');
      final release = UpdateRelease.fromManifest(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>,
        me.abi,
      );
      _saved = _saved.copyWith(checked: deps.now(), latest: release);
      if (release == null || release.versionCode <= me.versionCode) {
        _saved = _saved.copyWith(clearLatest: true);
        await _save();
        state = const UpdateUpToDate();
        return;
      }
      await _save();
      // Already downloaded and checked: straight to "Install".
      final done = File(await _apkPath(release));
      if (done.existsSync() && done.lengthSync() == release.size) {
        state = UpdateReady(release, done.path);
      } else {
        state = UpdateAvailable(release);
      }
    } on Object {
      if (manual) {
        state = const UpdateFailed(
          "Couldn't reach GitHub. Check your connection and try again.",
        );
      } else {
        state = keep is UpdateChecking ? const UpdateIdle() : keep;
      }
    }
  }

  /// The release the last check found, if it's still newer than this Idris.
  Future<void> _showSaved() async {
    final r = _saved.latest;
    if (r == null) return;
    try {
      if (r.versionCode <= (await _deps!.platform.info()).versionCode) return;
      final done = File(await _apkPath(r));
      state = done.existsSync() && done.lengthSync() == r.size
          ? UpdateReady(r, done.path)
          : UpdateAvailable(r);
    } on Object {
      // Leave it for the next check.
    }
  }

  Future<String> _apkPath(UpdateRelease r) async =>
      '${(await _folder()).path}/${r.versionCode}.apk';

  /// Downloads [UpdateAvailable]'s release, resuming a partial download,
  /// then checks its size, hash and signer.
  Future<void> download() async {
    final release = state.release;
    if (release == null || _downloading) return;
    _downloading = true;
    final deps = _deps!;
    final path = await _apkPath(release);
    final part = File('$path.part');
    var have = part.existsSync() ? part.lengthSync() : 0;
    if (have > release.size) {
      part.deleteSync();
      have = 0;
    }
    state = UpdateDownloading(release, have);
    IOSink? sink;
    try {
      final res = await _get(deps.client, Uri.parse(release.url), from: have);
      if (res.statusCode == 200) {
        have = 0; // the server sent it all again
        sink = part.openWrite();
      } else if (res.statusCode == 206) {
        sink = part.openWrite(mode: FileMode.append);
      } else if (res.statusCode == 416 && have == release.size) {
        // Already all here.
      } else {
        throw HttpException('${res.statusCode}');
      }
      if (sink != null) {
        var shown = DateTime.fromMillisecondsSinceEpoch(0);
        await for (final chunk in res.stream.timeout(
          const Duration(seconds: 30),
        )) {
          sink.add(chunk);
          have += chunk.length;
          final now = DateTime.now();
          if (now.difference(shown) > const Duration(milliseconds: 120)) {
            shown = now;
            state = UpdateDownloading(release, have);
          }
        }
        await sink.flush();
        await sink.close();
        sink = null;
      }
      state = UpdateDownloading(release, have);
      if (part.lengthSync() != release.size) {
        throw const _Damaged();
      }
      if (await _sha256(part) != release.sha256) {
        part.deleteSync();
        throw const _Damaged();
      }
      final apk = part.renameSync(path);
      final me = await deps.platform.info();
      final c = await deps.platform.check(apk.path);
      if (!c.valid || c.package != 'com.isg32.idris') {
        apk.deleteSync();
        throw const _Damaged();
      }
      if (!c.sameSigner) {
        apk.deleteSync();
        state = UpdateFailed(
          'This copy of Idris was installed another way, so it can\'t '
          'update itself. Uninstall it once and install the latest from '
          'GitHub; after that, updates come right here.',
          release: release,
          reinstall: true,
        );
        return;
      }
      // 0: the file doesn't say (an AppImage); update.json's is trusted.
      if (c.versionCode != 0 && c.versionCode <= me.versionCode) {
        apk.deleteSync();
        state = const UpdateUpToDate();
        return;
      }
      state = UpdateReady(release, apk.path);
    } on _Damaged {
      state = UpdateFailed(
        'The download was damaged. Try again.',
        release: release,
      );
    } on Object {
      // Kept: the next try carries on where this one stopped.
      state = UpdateFailed(
        'The download stopped (${megabytes(have)} of '
        '${release.sizeLabel}). Try again to carry on.',
        release: release,
      );
    } finally {
      await sink?.close();
      _downloading = false;
    }
  }

  /// Follows GitHub's redirects by hand, so the Range header goes along.
  Future<http.StreamedResponse> _get(
    http.Client client,
    Uri url, {
    required int from,
  }) async {
    var at = url;
    for (var hop = 0; hop < 6; hop++) {
      final req = http.Request('GET', at)..followRedirects = false;
      if (from > 0) req.headers['range'] = 'bytes=$from-';
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.isRedirect || (res.statusCode >= 300 && res.statusCode < 400)) {
        final next = res.headers['location'];
        await res.stream.drain<void>();
        if (next == null) break;
        at = at.resolve(next);
        continue;
      }
      return res;
    }
    throw const HttpException('too many redirects');
  }

  static Future<String> _sha256(File f) async =>
      (await sha256.bind(f.openRead()).first).toString();

  /// Installs the downloaded release, asking for "Install unknown apps"
  /// first if Idris doesn't have it yet.
  Future<void> install() async {
    final s = state;
    final (release, path) = switch (s) {
      UpdateReady(:final release, :final path) => (release, path),
      UpdateNeedsPermission(:final release, :final path) => (release, path),
      _ => (null, null),
    };
    if (release == null || path == null) return;
    final deps = _deps!;
    try {
      if (!File(path).existsSync()) {
        state = UpdateAvailable(release);
        return;
      }
      if (!(await deps.platform.info()).canInstall) {
        state = UpdateNeedsPermission(release, path);
        return;
      }
      // Remembered, so the next launch can say what's new.
      _saved = _saved.copyWith(installing: release);
      await _save();
      state = UpdateInstalling(release, path);
      await deps.platform.install(path);
    } on Object {
      state = UpdateFailed(
        "Couldn't start the install. Try again.",
        release: release,
      );
    }
  }

  /// Starts the installed (new) Idris and closes this one (the AppImage,
  /// after [UpdateRestartNeeded]).
  Future<void> restart() async => _deps?.platform.restart();

  /// Opens Android's "Install unknown apps" switch for Idris.
  Future<void> allowInstalls() async {
    try {
      await _deps?.platform.openInstallSettings();
    } on Object {
      // Nothing to open.
    }
  }

  void _onResult(InstallResult r) {
    final s = state;
    if (s is! UpdateInstalling) return;
    switch (r.code) {
      case InstallResult.pendingUser:
        state = UpdateInstalling(s.release, s.path, confirming: true);
      case InstallResult.success:
        // Android replaces Idris and closes it; the AppImage replaced
        // itself and takes over on a restart.
        state = _deps!.platform.restartsToFinish
            ? UpdateRestartNeeded(s.release)
            : UpdateInstalling(s.release, s.path);
      case InstallResult.aborted:
        state = UpdateReady(s.release, s.path);
      default:
        _saved = _saved.copyWith(clearInstalling: true);
        unawaited(_save());
        state = UpdateFailed(
          r.code == 7
              ? "This update doesn't fit this phone."
              : r.code == 6
              ? 'Not enough space on the phone to install it.'
              : "Couldn't install it${r.message == null ? '' : ' (${r.message})'}. Try again.",
          release: s.release,
        );
    }
  }

  /// Hides Home's card for this version (Settings still shows it).
  Future<void> dismiss() async {
    final r = state.release;
    if (r == null) return;
    _saved = _saved.copyWith(dismissed: r.version);
    ref.read(dismissedUpdateProvider.notifier).set(r.version);
    await _save();
  }

  /// Leaves a failure (back to what's available).
  void clearFailure() {
    final s = state;
    if (s is! UpdateFailed) return;
    state = s.release != null
        ? UpdateAvailable(s.release!)
        : const UpdateIdle();
  }

  /// Deletes downloads for versions at or below [installed].
  Future<void> _tidy(int installed) async {
    final d = await _folder();
    for (final f in d.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      final code = int.tryParse(name.split('.').first);
      if (code != null && code <= installed) {
        try {
          f.deleteSync();
        } on Object {
          // Next time.
        }
      }
    }
  }
}

class _Damaged implements Exception {
  const _Damaged();
}

/// What the updater keeps between launches.
class _Saved {
  const _Saved({this.checked, this.latest, this.dismissed, this.installing});

  final DateTime? checked;
  final UpdateRelease? latest;
  final String? dismissed;

  /// The release handed to Android, for "What's new" after it's in.
  final UpdateRelease? installing;

  _Saved copyWith({
    DateTime? checked,
    UpdateRelease? latest,
    String? dismissed,
    UpdateRelease? installing,
    bool clearLatest = false,
    bool clearInstalling = false,
  }) => _Saved(
    checked: checked ?? this.checked,
    latest: clearLatest ? null : (latest ?? this.latest),
    dismissed: dismissed ?? this.dismissed,
    installing: clearInstalling ? null : (installing ?? this.installing),
  );

  Map<String, Object?> toJson() => {
    'checked': checked?.toIso8601String(),
    'latest': latest?.toJson(),
    'dismissed': dismissed,
    'installing': installing?.toJson(),
  };

  factory _Saved.fromJson(Map<String, Object?> j) => _Saved(
    checked: DateTime.tryParse((j['checked'] as String?) ?? ''),
    latest: UpdateRelease.fromJson(j['latest']),
    dismissed: j['dismissed'] as String?,
    installing: UpdateRelease.fromJson(j['installing']),
  );
}

/// The real [UpdateDeps] on Android.
UpdateDeps? phoneUpdateDeps() {
  final UpdatePlatform? platform = Platform.isAndroid
      ? ChannelUpdatePlatform()
      // Only the AppImage updates itself; a development build doesn't.
      : Platform.isLinux
      ? AppImageUpdatePlatform.running()
      : null;
  if (platform == null) return null;
  return UpdateDeps(
    platform: platform,
    client: http.Client(),
    dir: getApplicationSupportDirectory,
  );
}

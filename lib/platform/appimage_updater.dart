import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../features/settings/about_page.dart';
import 'updater_channel.dart';

/// Over-the-air updates for the Linux AppImage. The AppImage is one file
/// (its path is in `$APPIMAGE`), so installing a new one is replacing that
/// file: copied beside it, made executable, then renamed over it, which is
/// atomic, so a failed update never leaves a broken Idris. The running
/// copy carries on until the user restarts it.
///
/// There's no signature to check, as Android checks an APK's: the download
/// comes over HTTPS from GitHub, and its size and SHA-256 must match
/// update.json (see Updater.download).
class AppImageUpdatePlatform implements UpdatePlatform {
  AppImageUpdatePlatform(this.appImage);

  /// The running AppImage.
  final String appImage;

  /// The AppImage this machine runs, or null when Idris isn't running as
  /// one (a development build): then it doesn't update itself.
  static AppImageUpdatePlatform? running() {
    final path = Platform.environment['APPIMAGE'];
    if (path == null || path.isEmpty || !File(path).existsSync()) return null;
    return AppImageUpdatePlatform(path);
  }

  final _results = StreamController<InstallResult>.broadcast();

  @override
  Stream<InstallResult> get results => _results.stream;

  @override
  bool get restartsToFinish => true;

  @override
  Future<Installed> info() async => const Installed(
    versionCode: kAppBuild,
    versionName: kAppVersion,
    abi: 'linux-x86_64',
    // Whether the update can be written where the AppImage is.
    canInstall: true,
  );

  /// An AppImage is an ELF program; its version isn't readable from
  /// outside, so it's 0 (the Updater then trusts update.json's).
  @override
  Future<ApkCheck> check(String path) async {
    final f = File(path);
    final head = f.existsSync() ? await f.openRead(0, 4).first : <int>[];
    final elf =
        head.length == 4 &&
        head[0] == 0x7f &&
        head[1] == 0x45 &&
        head[2] == 0x4c &&
        head[3] == 0x46;
    return ApkCheck(valid: elf, package: 'com.isg32.idris', sameSigner: true);
  }

  @override
  Future<void> openInstallSettings() async {}

  @override
  Future<void> install(String path) async {
    final next = File(
      p.join(p.dirname(appImage), '.${p.basename(appImage)}.new'),
    );
    try {
      await File(path).copy(next.path);
      final chmod = await Process.run('chmod', ['755', next.path]);
      if (chmod.exitCode != 0) throw StateError('chmod: ${chmod.stderr}');
      await next.rename(appImage);
      await File(path).delete();
      _results.add(const InstallResult(InstallResult.success));
    } on Object catch (e) {
      if (next.existsSync()) await next.delete();
      _results.add(InstallResult(1, '$e'));
    }
  }

  @override
  Future<void> restart() async {
    await Process.start(appImage, const [], mode: ProcessStartMode.detached);
    exit(0);
  }
}

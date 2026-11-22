import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:idris/platform/appimage_updater.dart';
import 'package:idris/platform/updater_channel.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('idris_appimage_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  const elf = [0x7f, 0x45, 0x4c, 0x46];

  test('an update replaces the running AppImage in place', () async {
    final running = File('${tmp.path}/Idris-x86_64.AppImage')
      ..writeAsBytesSync([...elf, 1, 1, 1]);
    final download = File('${tmp.path}/downloads/17.apk')
      ..createSync(recursive: true)
      ..writeAsBytesSync([...elf, 2, 2, 2, 2]);
    final platform = AppImageUpdatePlatform(running.path);

    expect((await platform.check(download.path)).valid, isTrue);
    final result = platform.results.first;
    await platform.install(download.path);
    expect((await result).code, InstallResult.success);

    expect(running.readAsBytesSync(), [...elf, 2, 2, 2, 2]);
    expect(download.existsSync(), isFalse);
    // Executable, and no half-written copy left beside it.
    expect(running.statSync().modeString(), startsWith('rwx'));
    expect(
      tmp.listSync().map((e) => e.path.split('/').last),
      isNot(contains(startsWith('.Idris'))),
    );
  });

  test('what isn\'t a program is refused', () async {
    final notElf = File('${tmp.path}/page.html')..writeAsStringSync('<html>');
    final platform = AppImageUpdatePlatform('${tmp.path}/x.AppImage');
    expect((await platform.check(notElf.path)).valid, isFalse);
  });
}

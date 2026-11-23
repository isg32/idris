import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:idris/platform/desktop_entry.dart';

void main() {
  late Directory tmp;
  late Map<String, String> env;
  late File entry;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('idris_desktop_');
    final appDir = Directory('${tmp.path}/mount')..createSync();
    File('${appDir.path}/idris.png').writeAsBytesSync([1, 2, 3]);
    env = {
      'APPIMAGE': '${tmp.path}/Applications/Idris-x86_64.AppImage',
      'APPDIR': appDir.path,
      'HOME': '${tmp.path}/home',
    };
    entry = File(
      '${tmp.path}/home/.local/share/applications/com.isg32.idris.desktop',
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('run as an AppImage, it adds itself to the app menu', () async {
    await registerDesktopEntry(env: env);
    final text = entry.readAsStringSync();
    expect(text, contains('Exec="${env['APPIMAGE']}"'));
    expect(text, contains('StartupWMClass=com.isg32.idris'));
    final icon = File(
      '${tmp.path}/home/.local/share/icons/hicolor/192x192/apps/'
      'com.isg32.idris.png',
    );
    expect(icon.readAsBytesSync(), [1, 2, 3]);
    expect(text, contains('Icon=${icon.path}'));
  });

  test('moved, the entry follows on the next launch', () async {
    await registerDesktopEntry(env: env);
    await registerDesktopEntry(
      env: {...env, 'APPIMAGE': '${tmp.path}/elsewhere/Idris.AppImage'},
    );
    expect(
      entry.readAsStringSync(),
      contains('Exec="${tmp.path}/elsewhere/Idris.AppImage"'),
    );
  });

  test('an entry already right is left alone', () async {
    await registerDesktopEntry(env: env);
    final written = entry.lastModifiedSync();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await registerDesktopEntry(env: env);
    expect(entry.lastModifiedSync(), written);
  });

  test('not an AppImage (a development build): nothing is written', () async {
    await registerDesktopEntry(env: {...env}..remove('APPIMAGE'));
    expect(entry.existsSync(), isFalse);
  });

  test('a path with spaces and quotes is quoted for Exec', () {
    final text = desktopEntry(
      appImage: r'/home/me/My Apps/"Idris"$.AppImage',
      icon: '/i.png',
    );
    expect(text, contains(r'Exec="/home/me/My Apps/\"Idris\"\$.AppImage"'));
  });

  test('XDG_DATA_HOME is respected', () async {
    await registerDesktopEntry(
      env: {...env, 'XDG_DATA_HOME': '${tmp.path}/xdg'},
    );
    expect(
      File('${tmp.path}/xdg/applications/com.isg32.idris.desktop').existsSync(),
      isTrue,
    );
  });
}

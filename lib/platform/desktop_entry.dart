import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Puts the AppImage in the desktop's app menu: an AppImage installs
/// nothing, so app launchers (wofi, rofi, fuzzel, a desktop's app grid)
/// don't list it until a `.desktop` entry exists. On every launch as an
/// AppImage, Idris writes its entry and icon into the user's data folder
/// (`~/.local/share/applications`, `.../icons`), pointing at wherever the
/// AppImage is now, so moving the file is followed on the next launch.
/// Files that are already right are left alone.
///
/// [env] is the process environment (a test passes its own).
Future<void> registerDesktopEntry({Map<String, String>? env}) async {
  final e = env ?? Platform.environment;
  final appImage = e['APPIMAGE'];
  final appDir = e['APPDIR'];
  final home = e['HOME'];
  if (appImage == null || appDir == null || home == null) return;
  final data = e['XDG_DATA_HOME'] ?? p.join(home, '.local', 'share');
  try {
    // The icon the AppImage carries (at its top: linuxdeploy puts it there).
    final icon = File(
      p.join(
        data,
        'icons',
        'hicolor',
        '192x192',
        'apps',
        'com.isg32.idris.png',
      ),
    );
    final bundled = File(p.join(appDir, 'idris.png'));
    if (bundled.existsSync() &&
        (!icon.existsSync() || icon.lengthSync() != bundled.lengthSync())) {
      await icon.parent.create(recursive: true);
      await bundled.copy(icon.path);
    }
    final entry = File(p.join(data, 'applications', 'com.isg32.idris.desktop'));
    final content = desktopEntry(appImage: appImage, icon: icon.path);
    if (!entry.existsSync() || await entry.readAsString() != content) {
      await entry.parent.create(recursive: true);
      await entry.writeAsString(content);
    }
  } on Object catch (err) {
    debugPrint('Could not add Idris to the app menu: $err');
  }
}

/// The `.desktop` entry for the AppImage at [appImage].
String desktopEntry({required String appImage, required String icon}) {
  // Exec quotes the path (it may have spaces), escaping what the
  // Desktop Entry spec says must be escaped inside quotes.
  final exec = appImage.replaceAllMapped(
    RegExp(r'["`$\\]'),
    (m) => '\\${m[0]}',
  );
  return '''
[Desktop Entry]
Type=Application
Name=Idris
GenericName=Music player
Comment=Your mantras and calm music, from your own YouTube playlists
Exec="$exec"
Icon=$icon
Terminal=false
Categories=AudioVideo;Audio;Player;
Keywords=music;mantra;youtube;playlist;
StartupWMClass=com.isg32.idris
X-AppImage-Path=$appImage
''';
}

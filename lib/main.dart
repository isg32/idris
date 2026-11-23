import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service_mpris/audio_service_mpris.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'app/app.dart';
import 'app/router.dart';
import 'data/db/database.dart';
import 'data/library.dart';
import 'data/providers.dart';
import 'platform/audio_handler.dart';
import 'platform/cache_manager.dart';
import 'platform/covers.dart';
import 'platform/local_music.dart';
import 'platform/crash_log.dart';
import 'platform/desktop_entry.dart';
import 'platform/updater.dart';
import 'features/crash_overlay.dart';
import 'features/settings/about_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // First, so errors from here on are logged and shown, not lost.
  CrashLog.instance
    ..appVersion = kAppVersion
    ..install();
  ErrorWidget.builder = quietErrorWidget;
  _registerFontLicences();
  // On Linux, just_audio plays through libmpv (media_kit).
  if (Platform.isLinux) {
    JustAudioMediaKit.ensureInitialized(linux: true);
    // Media controls on Linux: MPRIS on the session bus, which media keys,
    // playerctl and desktop media widgets talk to.
    AudioServiceMpris.init(
      dBusName: 'idris',
      identity: 'Idris',
      desktopEntry: 'com.isg32.idris',
      canControl: true,
      canPlay: true,
      canPause: true,
      canGoNext: true,
      canGoPrevious: true,
    );
  }
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));

  final library = Library(AppDatabase());
  final local = LocalMusic(
    library,
    Platform.isLinux ? DiskLocalMusic() : ChannelLocalMusic(),
  );
  final cache = CacheManager(library, local: local);
  final covers = Covers();
  // Covers of playlists and tracks that are gone.
  unawaited(library.coverPaths().then(covers.tidy).catchError((Object _) {}));
  // Playback runs as a media service, so it carries on in the background.
  final handler = await initAudio(library: library, cache: cache);
  final onboarded =
      (await library.db.select(library.db.prefs).get()).any(
        (p) => p.key == 'onboarded',
      ) ||
      (await library.allPlaylists()).isNotEmpty;

  runApp(
    ProviderScope(
      overrides: [
        libraryProvider.overrideWithValue(library),
        cacheManagerProvider.overrideWithValue(cache),
        coversProvider.overrideWithValue(covers),
        localMusicProvider.overrideWithValue(local),
        audioHandlerProvider.overrideWithValue(handler),
        // Over-the-air updates from GitHub Releases (Android only).
        updateDepsProvider.overrideWithValue(phoneUpdateDeps()),
      ],
      child: IdrisApp(router: buildRouter(onboarded: onboarded)),
    ),
  );
  unawaited(CrashLog.instance.checkLastRun());
  // Run as an AppImage: be in the desktop's app menu.
  if (Platform.isLinux) unawaited(registerDesktopEntry());
}

/// Doto and Inter are bundled under the SIL Open Font License.
void _registerFontLicences() {
  for (final (font, file) in const [
    ('Doto', 'assets/fonts/OFL-Doto.txt'),
    ('Inter', 'assets/fonts/OFL-Inter.txt'),
  ]) {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([
        font,
      ], await rootBundle.loadString(file));
    });
  }
}

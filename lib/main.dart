import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/router.dart';
import 'data/db/database.dart';
import 'data/library.dart';
import 'data/providers.dart';
import 'platform/audio_handler.dart';
import 'platform/cache_manager.dart';
import 'platform/crash_log.dart';
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
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));

  final library = Library(AppDatabase());
  final cache = CacheManager(library);
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
        audioHandlerProvider.overrideWithValue(handler),
      ],
      child: IdrisApp(router: buildRouter(onboarded: onboarded)),
    ),
  );
  unawaited(CrashLog.instance.checkLastRun());
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

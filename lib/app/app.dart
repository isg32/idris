import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/v_colors.dart';
import '../core/theme/v_palette.dart';
import '../core/theme/v_text.dart';
import '../core/theme/v_theme.dart';
import '../data/providers.dart';
import '../platform/glyph.dart';

/// Follows the system light/dark setting; there is no in-app toggle.
class IdrisApp extends ConsumerStatefulWidget {
  const IdrisApp({super.key, required this.router});

  final GoRouter router;

  @override
  ConsumerState<IdrisApp> createState() => _IdrisAppState();
}

class _IdrisAppState extends ConsumerState<IdrisApp>
    with WidgetsBindingObserver {
  AppLifecycleState _life = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_startup());
  }

  /// Syncs playlists (when Settings allows) and starts pre-caching.
  Future<void> _startup() async {
    ref.read(cacheManagerProvider).startWorker();
    final settings = await ref.read(libraryProvider).settings();
    if (settings.syncOnOpen) {
      final r = await ref.read(syncProvider)();
      if (mounted) ref.read(lastSyncProvider.notifier).set(r);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    GlyphBreath.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _life = state);
  }

  /// The breathing glyph runs while audio plays, the setting is on, and
  /// the app is in front (Nothing allows nothing else).
  void _syncGlyph() {
    final on =
        (ref.watch(settingsProvider).value?.glyph ?? false) &&
        (ref.watch(playingProvider).value ?? false) &&
        _life == AppLifecycleState.resumed;
    if (on) {
      unawaited(GlyphBreath.instance.start());
    } else {
      GlyphBreath.instance.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncGlyph();
    final palette = VPalette.of(context);
    return CupertinoApp.router(
      title: 'Idris',
      debugShowCheckedModeBanner: false,
      theme: VTheme.of(palette),
      color: palette.paper,
      routerConfig: widget.router,
      builder: (context, child) {
        final p = VPalette.of(context);
        final icons = p.isDark ? Brightness.light : Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: VColors.transparent,
            systemNavigationBarColor: VColors.transparent,
            statusBarIconBrightness: icons,
            systemNavigationBarIconBrightness: icons,
            statusBarBrightness: p.brightness,
          ),
          child: DefaultTextStyle(
            style: VText.body.copyWith(color: p.ink),
            child: ColoredBox(color: p.paper, child: child),
          ),
        );
      },
    );
  }
}

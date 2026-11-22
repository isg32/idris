import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/icons/v_icons.dart';
import '../core/theme/v_colors.dart';
import '../core/theme/v_text.dart';
import '../core/theme/v_tokens.dart';
import '../core/widgets/v_buttons.dart';
import '../core/widgets/v_ink.dart';
import '../data/providers.dart';
import '../features/common.dart';
import '../platform/local_music.dart';
import '../platform/playback_rules.dart';
import 'router.dart';

/// The desktop window: a sidebar on the left (the sections and the
/// playlists), the page in the middle (no wider than reads well), and a
/// now-playing bar along the bottom. Every page, the player included,
/// opens beside the sidebar.
class DesktopFrame extends StatelessWidget {
  const DesktopFrame({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  /// Pages are no wider than this; the window's extra width is margin.
  static const double pageWidth = 1120;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final line = BorderSide(color: ink, width: VSpace.hairline);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(border: Border(right: line)),
          child: SizedBox(width: 248, child: _Sidebar(router)),
        ),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: pageWidth),
                    child: child,
                  ),
                ),
              ),
              _NowPlayingBar(router),
            ],
          ),
        ),
      ],
    );
  }
}

/// Where the router is, to light the sidebar's row for it.
String _here(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

class _Sidebar extends ConsumerWidget {
  const _Sidebar(this.router);
  final GoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider).value ?? const [];
    return ListenableBuilder(
      listenable: router.routerDelegate,
      builder: (context, _) {
        final here = _here(router);
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 28, 12, 8),
              sliver: SliverList.list(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 20),
                    child: Text('Idris', style: VText.doto(30, weight: 800)),
                  ),
                  _Item(
                    icon: VIcon.home,
                    label: 'Home',
                    on: here == Routes.home,
                    onTap: () => router.go(Routes.home),
                  ),
                  _Item(
                    icon: VIcon.library,
                    label: 'Library',
                    on: here == Routes.library,
                    onTap: () => router.go(Routes.library),
                  ),
                  _Item(
                    icon: VIcon.phone,
                    label: localLabel,
                    on: here == Routes.local,
                    onTap: () => _open(Routes.local),
                  ),
                  _Item(
                    icon: VIcon.gear,
                    label: 'Settings',
                    on: here == Routes.settings,
                    onTap: () => router.go(Routes.settings),
                  ),
                  if (playlists.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 28, 8, 8),
                      child: Text('PLAYLISTS', style: VText.eyebrow),
                    ),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 24),
              sliver: SliverList.builder(
                itemCount: playlists.length,
                itemBuilder: (context, i) {
                  final s = playlists[i];
                  final route = Routes.playlist(s.id);
                  return _Item(
                    leading: PlaylistCover(s.playlist, size: 32, radius: 8),
                    label: s.title,
                    on: here == route,
                    onTap: () => _open(route),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// Opens a page over the current section, or swaps it if one is open.
  void _open(String route) {
    final here = _here(router);
    if (here == route) return;
    if (here.startsWith('/playlist/') || here == Routes.local) {
      router.pushReplacement(route);
    } else {
      router.push(route);
    }
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.label,
    required this.on,
    required this.onTap,
    this.icon,
    this.leading,
  });

  final VIcon? icon;
  final Widget? leading;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(
        children: [
          leading ??
              SizedBox.square(
                dimension: 32,
                child: Center(child: VIconView(icon!, size: 20)),
              ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: VText.inter(14, weight: on ? 600 : 400),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      selected: on,
      child: VTappable(
        haptic: false,
        onTap: onTap,
        // The section open now: inverted, as the playing track's row is.
        child: on
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: VInkScope.inverted(
                  context,
                  child: ColoredBox(color: VInk.of(context), child: row),
                ),
              )
            : row,
      ),
    );
  }
}

/// What's playing, along the bottom of the window: the track, the
/// controls and a progress line you can click to seek. Click the track for
/// the full player.
class _NowPlayingBar extends ConsumerWidget {
  const _NowPlayingBar(this.router);
  final GoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider);
    final t = s.current;
    if (t == null) return const SizedBox.shrink();
    final handler = ref.read(audioHandlerProvider);
    final playing = ref.watch(playingProvider).value ?? false;
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final dur =
        ref.watch(durationProvider).value ??
        (t.durationMs > 0 ? Duration(milliseconds: t.durationMs) : null);
    final ink = VInk.of(context);

    void openPlayer() {
      if (_here(router) != Routes.player) {
        unawaited(router.push(Routes.player, extra: 0.0));
      }
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: ink, width: VSpace.hairline),
        ),
      ),
      child: SizedBox(
        height: 84,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: VTappable(
                  haptic: false,
                  onTap: openPlayer,
                  child: Row(
                    children: [
                      TrackArt(t.videoId, size: 52, radius: 10),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: VText.rowTitle,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              s.loading
                                  ? 'Opening…'
                                  : [
                                      if (t.channel.isNotEmpty) t.channel,
                                      if (s.source.isNotEmpty) s.source,
                                    ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: VText.secondary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 4,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _Control(
                          icon: VIcon.shuffle,
                          label: 'Shuffle',
                          on: s.shuffle,
                          onTap: () => handler.setShuffle(!s.shuffle),
                        ),
                        _Control(
                          icon: VIcon.previous,
                          label: 'Previous',
                          onTap: () => unawaited(handler.skipToPrevious()),
                        ),
                        _Control(
                          icon: playing ? VIcon.pause : VIcon.play,
                          label: playing ? 'Pause' : 'Play',
                          big: true,
                          onTap: () => unawaited(handler.toggle()),
                        ),
                        _Control(
                          icon: VIcon.next,
                          label: 'Next',
                          onTap: s.canSkip
                              ? () => unawaited(handler.skipToNext())
                              : null,
                        ),
                        _Control(
                          icon: s.loop == Loop.one ? VIcon.loop : VIcon.loopAll,
                          label: 'Loop',
                          on: s.loop != Loop.off,
                          onTap: handler.cycleLoop,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        SizedBox(
                          width: 44,
                          child: Text(
                            VFormat.clock(pos),
                            textAlign: TextAlign.right,
                            style: VText.inter(11, weight: 300),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _Seek(
                            value: dur == null || dur.inMilliseconds == 0
                                ? 0
                                : pos.inMilliseconds / dur.inMilliseconds,
                            onSeek: dur == null
                                ? null
                                : (f) => handler.seek(dur * f),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 44,
                          child: Text(
                            dur == null ? '' : VFormat.clock(dur),
                            style: VText.inter(11, weight: 300),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 3,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _Control(
                    icon: VIcon.queue,
                    label: 'Open the player',
                    onTap: openPlayer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Control extends StatelessWidget {
  const _Control({
    required this.icon,
    required this.label,
    this.onTap,
    this.on = false,
    this.big = false,
  });

  final VIcon icon;
  final String label;
  final VoidCallback? onTap;

  /// A toggle that's switched on (shuffle, loop): drawn inverted.
  final bool on;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final size = big ? 44.0 : 36.0;
    final glyph = VIconView(icon, size: big ? 22 : 18, strokeWidth: 1.8);
    return Semantics(
      button: true,
      label: label,
      child: Opacity(
        opacity: onTap == null ? VColors.disabledOpacity : 1,
        child: VTappable(
          haptic: false,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox.square(
              dimension: size,
              child: big || on
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: VInk.of(context),
                        shape: BoxShape.circle,
                      ),
                      child: VInkScope.inverted(
                        context,
                        child: Center(child: glyph),
                      ),
                    )
                  : Center(child: glyph),
            ),
          ),
        ),
      ),
    );
  }
}

/// A thin progress line: click or drag along it to seek.
class _Seek extends StatelessWidget {
  const _Seek({required this.value, this.onSeek});

  final double value;
  final void Function(double fraction)? onSeek;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        void at(Offset p) => onSeek?.call((p.dx / c.maxWidth).clamp(0.0, 1.0));
        return MouseRegion(
          cursor: onSeek == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => at(d.localPosition),
            onHorizontalDragUpdate: (d) => at(d.localPosition),
            child: SizedBox(
              height: 16,
              child: Center(
                child: Stack(
                  children: [
                    Container(height: 2, color: ink.withValues(alpha: 0.25)),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: value.clamp(0.0, 1.0),
                      child: Container(height: 2, color: ink),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

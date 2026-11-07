import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/icons/v_icons.dart';
import '../../core/theme/v_colors.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';
import '../../data/providers.dart';
import '../common.dart';

/// The mini player's height (the shell and pages leave room for it).
const double miniPlayerHeight = 64;

/// What's playing, docked above the tab bar (as in Spotify and Apple
/// Music): artwork, title, play/pause and next, with a thin progress line.
/// Tap it for the full player. Hidden when nothing is playing.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider);
    final t = s.current;
    if (t == null) return const SizedBox.shrink();
    final handler = ref.read(audioHandlerProvider);
    final playing = ref.watch(playingProvider).value ?? false;
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final dur = ref.watch(durationProvider).value;
    final progress = dur == null || dur.inMilliseconds == 0
        ? 0.0
        : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
    final sub = s.loading
        ? 'Opening…'
        : s.repeatTarget != null
        ? '${s.repeatDone} / ${s.repeatTarget} · ${t.channel}'
        : t.channel;
    final ink = VInk.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.push(Routes.player),
        // Swipe up opens the player too.
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < -200) context.push(Routes.player);
        },
        child: VGlass(
          radius: 20,
          child: SizedBox(
            height: miniPlayerHeight,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 6, 8),
                  child: Row(
                    children: [
                      TrackArt(t.videoId, size: 48, radius: 12),
                      const SizedBox(width: 12),
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
                              sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: VText.secondary,
                            ),
                          ],
                        ),
                      ),
                      _IconTap(
                        icon: playing ? VIcon.pause : VIcon.play,
                        label: playing ? 'Pause' : 'Play',
                        onTap: () => unawaited(handler.toggle()),
                      ),
                      Opacity(
                        opacity: s.canSkip ? 1 : VColors.disabledOpacity,
                        child: _IconTap(
                          icon: VIcon.next,
                          label: 'Next',
                          onTap: s.canSkip
                              ? () => unawaited(handler.skipToNext())
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 0,
                  height: 2,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: progress,
                      child: ColoredBox(color: ink),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconTap extends StatelessWidget {
  const _IconTap({required this.icon, required this.label, this.onTap});

  final VIcon icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: VTappable(
      onTap: onTap,
      child: SizedBox.square(
        dimension: 44,
        child: Center(child: VIconView(icon, size: 22, strokeWidth: 1.8)),
      ),
    ),
  );
}

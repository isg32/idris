import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/format.dart';
import '../../core/icons/v_icons.dart';
import '../../core/theme/v_colors.dart';
import '../../core/theme/v_palette.dart';
import '../../core/theme/v_text.dart';
import '../../core/theme/v_tokens.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../platform/audio_handler.dart';
import '../../platform/playback_rules.dart';
import 'player_sheets.dart';

/// The full-screen player. Back keeps playing (Home shows "Now playing");
/// "Stop session" ends it.
class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider);
    final handler = ref.read(audioHandlerProvider);
    final t = s.current;
    final playing = ref.watch(playingProvider).value ?? false;
    final processing = ref.watch(processingProvider).value;
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final dur =
        ref.watch(durationProvider).value ??
        (t == null || t.durationMs == 0
            ? null
            : Duration(milliseconds: t.durationMs));
    final buffering = processing == ProcessingState.buffering;
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;

    final eyebrow = [
      if (s.source.isNotEmpty) s.source,
      if (s.loading)
        'Opening'
      else ...[
        if (s.kbps > 0) '${s.kbps} kbps',
        if (s.cached) 'Cached' else 'Streaming',
      ],
    ].join(' · ').toUpperCase();

    final art = t == null ? null : ref.watch(artworkProvider(t.videoId)).value;

    return CupertinoPageScaffold(
      backgroundColor: VInk.surfaceOf(context),
      child: Stack(
        children: [
          if (art != null) Positioned.fill(child: _Backdrop(art)),
          Positioned.fill(
            child: _content(
              context,
              ref,
              s,
              handler,
              t,
              playing,
              pos,
              dur,
              buffering,
              top,
              bottom,
              eyebrow,
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    SessionState s,
    IdrisAudioHandler handler,
    Track? t,
    bool playing,
    Duration pos,
    Duration? dur,
    bool buffering,
    double top,
    double bottom,
    String eyebrow,
  ) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, top + 12, 20, bottom + 24),
      child: t == null
          ? _Ended(onBack: () => context.pop())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    VTappable(
                      onTap: () => context.pop(),
                      child: Row(
                        children: [
                          const VIconView(VIcon.down, size: 16),
                          const SizedBox(width: 4),
                          Text('Back', style: VText.inter(14)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${s.index + 1} OF ${s.queue.length}',
                      style: VText.eyebrow,
                    ),
                  ],
                ),
                const SizedBox(height: 36),
                Text(eyebrow, style: VText.eyebrow),
                const SizedBox(height: 10),
                Text(
                  t.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: VText.inter(28, weight: 300, height: 1.2),
                ),
                if (t.channel.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(t.channel, style: VText.inter(13, weight: 300)),
                ],
                const SizedBox(height: 32),
                Text(
                  _clock(s.loading ? Duration.zero : pos),
                  style: VText.doto(56, weight: 900, height: 1),
                ),
                const SizedBox(height: 12),
                _SeekBar(
                  position: pos,
                  duration: dur,
                  onSeek: (d) => unawaited(handler.seek(d)),
                ),
                const SizedBox(height: 10),
                Text(
                  s.loading
                      ? 'Opening…'
                      : buffering
                      ? 'Buffering…'
                      : dur == null
                      ? ''
                      : 'of ${VFormat.clock(dur)}',
                  style: VText.secondary,
                ),
                if (s.problem != null) ...[
                  const SizedBox(height: 18),
                  VCard(
                    outline: VOutline.dashed,
                    child: Text(
                      s.problem!,
                      style: VText.inter(15, weight: 500),
                    ),
                  ),
                ] else if (s.repeatTarget != null) ...[
                  const SizedBox(height: 22),
                  _RepeatCounter(
                    done: s.repeatDone,
                    target: s.repeatTarget!,
                    then: s.repeatEnd.name == 'stop'
                        ? 'then stop'
                        : 'then next track',
                  ),
                ],
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    VCircleButton(
                      icon: VIcon.previous,
                      size: 56,
                      onTap: () => unawaited(handler.skipToPrevious()),
                    ),
                    const SizedBox(width: 28),
                    Opacity(
                      opacity: s.loading ? VColors.disabledOpacity : 1,
                      child: VCircleButton(
                        icon: playing ? VIcon.pause : VIcon.play,
                        filled: true,
                        size: 84,
                        onTap: s.loading
                            ? null
                            : () => unawaited(handler.toggle()),
                      ),
                    ),
                    const SizedBox(width: 28),
                    Opacity(
                      opacity: s.canSkip ? 1 : VColors.disabledOpacity,
                      child: VCircleButton(
                        icon: VIcon.next,
                        size: 56,
                        onTap: s.canSkip
                            ? () => unawaited(handler.skipToNext())
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _Mode(
                      label: switch (s.loop) {
                        Loop.off => 'Loop',
                        Loop.all => 'Playlist',
                        Loop.one => 'This one',
                      },
                      icon: s.loop == Loop.one ? VIcon.loop : VIcon.loopAll,
                      on: s.loop != Loop.off,
                      onTap: handler.cycleLoop,
                    ),
                    _Mode(
                      label: 'Repeat',
                      icon: VIcon.repeatCount,
                      text: s.repeatTarget == null
                          ? null
                          : '×${s.repeatTarget}',
                      on: s.repeatTarget != null,
                      onTap: () => showRepeatSheet(context, ref),
                    ),
                    _Mode(
                      label: 'Sleep',
                      icon: VIcon.timer,
                      text: _sleepText(s.sleepEndsAt, s.sleepAtEndOfTrack),
                      on: s.sleepEndsAt != null || s.sleepAtEndOfTrack,
                      onTap: () => showSleepSheet(context, ref),
                    ),
                    _Mode(
                      label: 'Shuffle',
                      icon: VIcon.shuffle,
                      on: s.shuffle,
                      onTap: () => handler.setShuffle(!s.shuffle),
                    ),
                    _Mode(
                      label: 'Queue',
                      icon: VIcon.queue,
                      on: false,
                      onTap: () => showQueueSheet(context, ref),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                VButton.ghost(
                  'Stop session',
                  onPressed: () async {
                    await handler.stop();
                    if (context.mounted) context.pop();
                  },
                ),
              ],
            ),
    );
  }

  static String _clock(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$sec' : '$m:$sec';
  }

  static String? _sleepText(DateTime? ends, bool atEnd) {
    if (atEnd) return 'End';
    if (ends == null) return null;
    final left = ends.difference(DateTime.now());
    if (left.inMinutes >= 1) return '${left.inMinutes}m';
    return '${left.inSeconds.clamp(0, 59)}s';
  }
}

/// The track's thumbnail, blurred to colour and light only, under a veil
/// so the ink stays readable (Settings → Artwork).
class _Backdrop extends StatelessWidget {
  const _Backdrop(this.file);

  final File file;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: Transform.scale(
            // Bigger than the screen so the blur has no soft edges.
            scale: 1.4,
            child: Image.file(file, fit: BoxFit.cover, gaplessPlayback: true),
          ),
        ),
        ColoredBox(color: VPalette.of(context).artScrim),
      ],
    );
  }
}

class _Ended extends StatelessWidget {
  const _Ended({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Spacer(),
      Text('Nothing playing', style: VText.doto(28)),
      const SizedBox(height: 10),
      Text(
        'Pick a track from Home or your Library.',
        style: VText.inter(14, weight: 300),
      ),
      const Spacer(),
      VButton.secondary('Back', onPressed: onBack),
    ],
  );
}

class _RepeatCounter extends StatelessWidget {
  const _RepeatCounter({
    required this.done,
    required this.target,
    required this.then,
  });

  final int done;
  final int target;
  final String then;

  @override
  Widget build(BuildContext context) => VCard(
    outline: VOutline.dashed,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('REPEAT', style: VText.eyebrow),
              const SizedBox(height: 4),
              Text(then, style: VText.secondary),
            ],
          ),
        ),
        Text.rich(
          TextSpan(
            text: '$done',
            style: VText.doto(40, weight: 900, height: 1),
            children: [TextSpan(text: ' / $target', style: VText.doto(20))],
          ),
        ),
      ],
    ),
  );
}

/// A mode toggle under the transport: outline when off, filled when on.
class _Mode extends StatelessWidget {
  const _Mode({
    required this.label,
    required this.icon,
    required this.on,
    required this.onTap,
    this.text,
  });

  final String label;
  final VIcon icon;
  final bool on;
  final String? text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    final fg = on ? VColors.onColor(ink) : ink;
    return VTappable(
      onTap: onTap,
      child: Semantics(
        button: true,
        toggled: on,
        label: label,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? ink : VColors.transparent,
                border: on ? null : Border.all(color: ink),
              ),
              alignment: Alignment.center,
              child: text != null
                  ? Text(text!, style: VText.doto(15).copyWith(color: fg))
                  : VIconView(icon, color: fg),
            ),
            const SizedBox(height: 6),
            Text(label, style: VText.inter(11, weight: on ? 600 : 500)),
          ],
        ),
      ),
    );
  }
}

/// The 6 px seek bar, with a knob you can drag.
class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  final Duration position;
  final Duration? duration;
  final ValueChanged<Duration> onSeek;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag;

  double get _value {
    final d = widget.duration;
    if (_drag != null) return _drag!;
    if (d == null || d.inMilliseconds == 0) return 0;
    return (widget.position.inMilliseconds / d.inMilliseconds).clamp(0, 1);
  }

  void _update(Offset local, double width) =>
      setState(() => _drag = (local.dx / width).clamp(0, 1));

  void _end() {
    final d = widget.duration;
    if (_drag != null && d != null) {
      widget.onSeek(d * _drag!);
    }
    setState(() => _drag = null);
  }

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (e) => _update(e.localPosition, w),
          onHorizontalDragUpdate: (e) => _update(e.localPosition, w),
          onHorizontalDragEnd: (_) => _end(),
          onTapUp: (e) {
            _update(e.localPosition, w);
            _end();
          },
          child: SizedBox(
            height: 24,
            child: Stack(
              alignment: Alignment.centerLeft,
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    border: Border.all(color: ink),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Container(
                  height: 6,
                  width: w * _value,
                  decoration: BoxDecoration(
                    color: ink,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Positioned(
                  left: (w * _value - 8).clamp(-8, w - 8),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: ink,
                      borderRadius: BorderRadius.circular(VRadius.pill),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

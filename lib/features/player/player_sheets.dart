import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/icons/v_icons.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_controls.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_surface.dart';
import '../../core/widgets/v_wheel.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../common.dart';

// ------------------------------------------------------------- repeat count

/// Repeat this track N times, then stop or move on.
Future<void> showRepeatSheet(BuildContext context, WidgetRef ref) =>
    showVSheet<void>(
      context,
      title: 'Repeat this track',
      builder: (_) => const _RepeatForm(),
    );

class _RepeatForm extends ConsumerStatefulWidget {
  const _RepeatForm();

  @override
  ConsumerState<_RepeatForm> createState() => _RepeatFormState();
}

class _RepeatFormState extends ConsumerState<_RepeatForm> {
  static const presets = [3, 9, 11, 21, 27, 54, 108];
  static final values = [for (var i = 2; i <= 1008; i++) i];

  late int _times = ref.read(sessionProvider).repeatTarget ?? 108;
  late RepeatEnd _end = ref.read(sessionProvider).repeatEnd;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    final t = s.current;
    final each = t == null || t.durationMs == 0
        ? null
        : Duration(milliseconds: t.durationMs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (t != null)
          Text(
            [
              t.title,
              if (each != null) '${VFormat.clock(each)} each',
              if (each != null) 'about ${VFormat.hm(each * _times)} in all',
            ].join(' · '),
            style: VText.secondary,
          ),
        const SizedBox(height: 8),
        Center(
          child: VWheel(
            key: ValueKey(_times),
            values: values,
            selected: _times,
            width: 140,
            onChanged: (v) => setState(() => _times = v),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in presets)
              VPill(
                '$p',
                fill: p == _times ? VFill.filled : VFill.outline,
                onTap: () => setState(() => _times = p),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: Text('When done', style: VText.rowTitle)),
            VSegmented<RepeatEnd>(
              segments: const {
                RepeatEnd.stop: 'Stop',
                RepeatEnd.next: 'Next track',
              },
              value: _end,
              onChanged: (v) => setState(() => _end = v),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: VButton.ghost(
                'Off',
                onPressed: () {
                  ref.read(audioHandlerProvider).setRepeat(null);
                  Navigator.of(context).pop();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: VButton.primary(
                'Repeat $_times times',
                onPressed: () {
                  ref.read(audioHandlerProvider).setRepeat(_times, end: _end);
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// --------------------------------------------------------------- sleep timer

/// Stop after some minutes, or at the end of the track.
Future<void> showSleepSheet(BuildContext context, WidgetRef ref) =>
    showVSheet<void>(
      context,
      title: 'Sleep timer',
      builder: (_) => const _SleepForm(),
    );

class _SleepForm extends ConsumerStatefulWidget {
  const _SleepForm();

  @override
  ConsumerState<_SleepForm> createState() => _SleepFormState();
}

class _SleepFormState extends ConsumerState<_SleepForm> {
  Timer? _tick;
  bool _custom = false;
  int _customMinutes = 90;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _set(Duration d) {
    ref.read(audioHandlerProvider).sleepIn(d);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    final handler = ref.read(audioHandlerProvider);
    final ends = s.sleepEndsAt;
    final active = ends != null || s.sleepAtEndOfTrack;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (active) ...[
          VCard(
            radius: 24,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.sleepAtEndOfTrack
                      ? 'End of track'
                      : VFormat.clock(
                          ends!.difference(DateTime.now()).isNegative
                              ? Duration.zero
                              : ends.difference(DateTime.now()),
                        ),
                  style: VText.doto(44, weight: 900, height: 1),
                ),
                const SizedBox(height: 6),
                Text(
                  s.sleepAtEndOfTrack
                      ? 'Stops when this track ends'
                      : 'left · stops at ${VFormat.time(ends!)}, fading out '
                            'over the last 10 s',
                  style: VText.secondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in const [15, 30, 45, 60])
              VPill('$m min', onTap: () => _set(Duration(minutes: m))),
            VPill(
              'End of track',
              fill: s.sleepAtEndOfTrack ? VFill.filled : VFill.outline,
              onTap: () {
                handler.sleepAtEndOfTrack();
                Navigator.of(context).pop();
              },
            ),
            VPill(
              'Custom',
              fill: _custom ? VFill.filled : VFill.dashed,
              onTap: () => setState(() => _custom = !_custom),
            ),
          ],
        ),
        if (_custom) ...[
          const SizedBox(height: 12),
          Center(
            child: VWheel(
              values: [for (var m = 5; m <= 240; m += 5) m],
              selected: _customMinutes,
              width: 140,
              format: (m) => VFormat.minutes(m),
              onChanged: (m) => setState(() => _customMinutes = m),
            ),
          ),
          const SizedBox(height: 12),
          VButton.primary(
            'Stop in ${VFormat.minutes(_customMinutes)}',
            onPressed: () => _set(Duration(minutes: _customMinutes)),
          ),
        ],
        if (active) ...[
          const SizedBox(height: 16),
          VButton.ghost(
            'Cancel timer',
            onPressed: () {
              handler.cancelSleep();
              Navigator.of(context).pop();
            },
          ),
        ],
      ],
    );
  }
}

// --------------------------------------------------------------------- queue

/// Now playing and up next, reorderable.
Future<void> showQueueSheet(BuildContext context, WidgetRef ref) =>
    showVSheet<void>(
      context,
      title: 'Queue',
      builder: (_) => const _QueueList(),
    );

class _QueueList extends ConsumerWidget {
  const _QueueList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider);
    final handler = ref.read(audioHandlerProvider);
    final current = s.current;
    final next = s.upNext;
    final left = next.fold<int>(0, (a, t) => a + t.durationMs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${next.length} up next · '
                '${VFormat.hm(Duration(milliseconds: left))}',
                style: VText.secondary,
              ),
            ),
            VPill(
              'Shuffle',
              fill: s.shuffle ? VFill.filled : VFill.outline,
              leading: const VIconView(VIcon.shuffle, size: 14),
              onTap: () => handler.setShuffle(!s.shuffle),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (current != null)
          VCard(
            inverted: true,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const VIconView(VIcon.playing, size: 16, strokeWidth: 2),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('NOW PLAYING', style: VText.eyebrow),
                      const SizedBox(height: 2),
                      Text(
                        current.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VText.inter(15, weight: 600),
                      ),
                    ],
                  ),
                ),
                if (s.repeatTarget != null)
                  Text(
                    '${s.repeatDone}/${s.repeatTarget}',
                    style: VText.doto(14),
                  ),
              ],
            ),
          ),
        if (next.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('UP NEXT', style: VText.eyebrow),
          const SizedBox(height: 10),
          VOutlined(
            radius: 20,
            child: ReorderableList(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: next.length,
              onReorderItem: handler.moveUpNext,
              proxyDecorator: (child, _, _) => VInkScope(
                ink: VInk.of(context),
                child: VOutlined(
                  radius: 18,
                  outline: VOutline.dashed,
                  fill: VInk.surfaceOf(context),
                  child: child,
                ),
              ),
              itemBuilder: (context, i) {
                final t = next[i];
                return Column(
                  key: ValueKey('${t.videoId}-$i'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (i > 0) const VDivider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: i,
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: VIconView(VIcon.drag, size: 18),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: VTappable(
                              onTap: () => unawaited(
                                handler.skipToQueueItem(s.index + 1 + i),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: VText.rowTitle,
                                  ),
                                  const SizedBox(height: 2),
                                  Consumer(
                                    builder: (context, ref, _) => Text(
                                      cacheWords(
                                        ref.watch(
                                          trackCacheStateProvider(t.videoId),
                                        ),
                                        ref.watch(
                                          cacheProgressProvider,
                                        )[t.videoId],
                                      ),
                                      style: VText.secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Text(trackLength(t), style: VText.doto(14)),
                          VTappable(
                            onTap: () => handler.removeUpNext(i),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: VIconView(VIcon.close, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          VButton.ghost('Clear up next', onPressed: handler.clearUpNext),
        ],
      ],
    );
  }
}

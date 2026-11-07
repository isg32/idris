import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/router.dart';
import '../core/format.dart';
import '../core/icons/v_icons.dart';
import '../core/theme/v_text.dart';
import '../core/theme/v_tokens.dart';
import '../core/widgets/v_buttons.dart';
import '../core/widgets/v_glass.dart';
import '../core/widgets/v_ink.dart';
import '../core/widgets/v_list.dart';
import '../core/widgets/v_progress.dart';
import '../core/widgets/v_surface.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../platform/youtube.dart';

/// `1:02:14`, `48:30`.
String trackLength(Track t) => t.durationMs == 0
    ? '–'
    : VFormat.clock(Duration(milliseconds: t.durationMs));

/// `18h 20m`, `42m`.
String totalLength(Duration d) => VFormat.hm(d);

/// `3.4 GB`, `640 MB`.
String formatBytes(int bytes) {
  const mb = 1024 * 1024;
  if (bytes >= 1024 * mb) {
    return '${(bytes / (1024 * mb)).toStringAsFixed(1)} GB';
  }
  return '${(bytes / mb).round()} MB';
}

/// "today 09:14", "yesterday", "3 days ago".
String when(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final days = DateTime(
    n.year,
    n.month,
    n.day,
  ).difference(DateTime(t.year, t.month, t.day)).inDays;
  return switch (days) {
    <= 0 => 'today · ${VFormat.time(t)}',
    1 => 'yesterday',
    _ => '$days days ago',
  };
}

/// The outlined tile that stands in for a thumbnail.
class ThumbTile extends StatelessWidget {
  const ThumbTile({super.key, this.size = 64, this.radius = 14, this.badge});

  final double size;
  final double radius;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: VOutlined(
              radius: radius,
              child: Center(child: VIconView(VIcon.wave, size: size * 0.4)),
            ),
          ),
          if (badge != null)
            Positioned(
              top: 10,
              left: 10,
              child: VPill.badge(badge!),
            ),
        ],
      ),
    );
  }
}

/// The small glyph at the end of a track row.
class CacheGlyph extends ConsumerWidget {
  const CacheGlyph(this.videoId, {super.key});

  final String videoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(trackCacheStateProvider(videoId));
    return switch (state) {
      TrackCacheState.pinned => const VIconView(VIcon.pin, size: 18),
      TrackCacheState.cached => const VIconView(VIcon.cached, size: 18),
      TrackCacheState.caching => SizedBox.square(
        dimension: 20,
        child: VRing(
          value: ref.watch(cacheProgressProvider)[videoId] ?? 0,
          size: 20,
          strokeWidth: 2.5,
        ),
      ),
      TrackCacheState.streams => const _Dashed(),
    };
  }
}

class _Dashed extends StatelessWidget {
  const _Dashed();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 18,
    child: VOutlined(
      radius: 999,
      outline: VOutline.dashed,
      child: SizedBox.expand(),
    ),
  );
}

/// The words under a track title for its cache state.
String cacheWords(TrackCacheState s, double? progress) => switch (s) {
  TrackCacheState.pinned => 'Pinned',
  TrackCacheState.cached => 'Cached',
  TrackCacheState.caching => 'Caching · ${((progress ?? 0) * 100).round()}%',
  TrackCacheState.streams => 'Streams',
};

/// A track in a list: number (or playing marker), title, state, length.
class TrackRow extends ConsumerWidget {
  const TrackRow({
    super.key,
    required this.track,
    this.number,
    this.subtitle,
    this.onTap,
    this.onLongPress,
  });

  final Track track;
  final int? number;
  final String? subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final playing = session.current?.videoId == track.videoId;
    final state = ref.watch(trackCacheStateProvider(track.videoId));
    final progress = ref.watch(cacheProgressProvider)[track.videoId];
    final sub =
        subtitle ??
        (playing
            ? session.repeatTarget != null
                  ? 'Playing · ${session.repeatDone} / ${session.repeatTarget}'
                  : 'Playing'
            : cacheWords(state, progress));
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          if (playing)
            const VIconView(VIcon.playing, size: 16, strokeWidth: 2)
          else if (number != null)
            SizedBox(
              width: 16,
              child: Text(
                '$number',
                textAlign: TextAlign.center,
                style: VText.doto(13),
              ),
            ),
          if (playing || number != null) const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VText.inter(15, weight: playing ? 600 : 500),
                ),
                const SizedBox(height: 3),
                Text(sub, style: VText.secondary),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(trackLength(track), style: VText.doto(14)),
          const SizedBox(width: 12),
          CacheGlyph(track.videoId),
        ],
      ),
    );
    final body = playing
        ? VInkScope.inverted(
            context,
            child: ColoredBox(color: VInk.of(context), child: row),
          )
        : row;
    return VTappable(onTap: onTap, onLongPress: onLongPress, child: body);
  }
}

/// Plays [tracks] from [index] and opens the player.
Future<void> playTracks(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks, {
  int index = 0,
  required String source,
  bool shuffle = false,
}) async {
  if (tracks.isEmpty) return;
  unawaited(context.push(Routes.player));
  await ref
      .read(audioHandlerProvider)
      .startSession(tracks, index: index, source: source, shuffle: shuffle);
}

/// Long-press on a track: play next, queue, pin, uncache, open on YouTube.
Future<void> showTrackActions(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  String source = '',
}) {
  final entry = ref.read(cacheEntriesProvider).value?[track.videoId];
  final pinned = track.pinned;
  final facts = [
    'Track',
    if (entry?.complete == true) 'Cached',
    if (entry != null && entry.kbps > 0) '${entry.kbps} kbps',
    if (entry?.complete == true) formatBytes(entry!.bytes),
  ].join(' · ');
  return showVSheet<void>(
    context,
    title: facts,
    builder: (sheet) {
      void done(FutureOr<void> Function() action) {
        Navigator.of(sheet).pop();
        unawaited(Future.sync(action));
      }

      final handler = ref.read(audioHandlerProvider);
      final library = ref.read(libraryProvider);
      final cache = ref.read(cacheManagerProvider);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(track.title, style: VText.inter(17, weight: 500)),
          const SizedBox(height: 14),
          VListSection(
            children: [
              VListRow(
                leading: const VIconView(VIcon.playNext),
                title: 'Play next',
                chevron: false,
                onTap: () => done(() => handler.playNext(track, source: source)),
              ),
              VListRow(
                leading: const VIconView(VIcon.queue),
                title: 'Add to queue',
                chevron: false,
                onTap: () =>
                    done(() => handler.addToQueue(track, source: source)),
              ),
              VListRow(
                leading: const VIconView(VIcon.pin),
                title: pinned ? 'Unpin' : 'Pin offline',
                value: pinned ? null : 'Never removed',
                chevron: false,
                onTap: () => done(() async {
                  await library.setTrackPinned(track.videoId, !pinned);
                  cache.kick();
                }),
              ),
              if (entry != null)
                VListRow(
                  leading: const VIconView(VIcon.trash),
                  title: 'Remove from cache',
                  chevron: false,
                  onTap: () => done(() async {
                    if (pinned) {
                      await library.setTrackPinned(track.videoId, false);
                    }
                    await cache.remove(track.videoId);
                  }),
                ),
              VListRow(
                leading: const VIconView(VIcon.external),
                title: 'Open on YouTube',
                chevron: false,
                onTap: () => done(
                  () => launchUrl(
                    watchUrl(track.videoId),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}

/// A section heading with an optional right-hand note.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.text, {super.key, this.note});

  final String text;
  final String? note;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: Text(text.toUpperCase(), style: VText.eyebrow)),
        if (note != null) Text(note!, style: VText.secondary),
      ],
    ),
  );
}

/// The slim "Offline — playing from cache" banner.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(connectivityProvider).value ?? true) {
      return const SizedBox.shrink();
    }
    return VOutlined(
      radius: VRadius.pill,
      outline: VOutline.dashed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const VIconView(VIcon.offline, size: 18),
            const SizedBox(width: 10),
            Text(
              'Offline — playing from cache',
              style: VText.inter(13, weight: 500),
            ),
          ],
        ),
      ),
    );
  }
}

/// A playlist card (Home and Library).
class PlaylistCard extends ConsumerWidget {
  const PlaylistCard({super.key, required this.summary, this.onLongPress});

  final PlaylistSummary summary;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = summary;
    final caching = s.pinned && !s.allCached;
    final subtitle = caching
        ? '${s.trackCount} tracks · ${s.cachedCount} of ${s.trackCount} cached'
        : '${s.trackCount} tracks · ${totalLength(s.total)}';
    return VCard(
      radius: VRadius.cardLarge,
      onTap: () => context.push(Routes.playlist(s.id)),
      onLongPress: onLongPress,
      child: Row(
        children: [
          const ThumbTile(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: VText.doto(20),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: VText.secondary),
                if (caching) ...[
                  const SizedBox(height: 6),
                  VBar(value: s.cachedCount / s.trackCount),
                ],
              ],
            ),
          ),
          if (!caching) ...[
            const SizedBox(width: 8),
            if (s.allCached)
              const VPill.badge('Offline')
            else
              const VPill('Online', fill: VFill.dashed),
          ],
        ],
      ),
    );
  }
}

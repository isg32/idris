import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/router.dart';
import '../core/format.dart';
import '../core/icons/v_icons.dart';
import '../core/layout.dart';
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
import '../platform/local_music.dart';
import '../platform/youtube.dart';
import 'player/player_sheet.dart';

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
            Positioned(top: 10, left: 10, child: VPill.badge(badge!)),
        ],
      ),
    );
  }
}

/// A track's thumbnail (Settings → Artwork), else the outlined tile.
class TrackArt extends ConsumerWidget {
  const TrackArt(
    this.videoId, {
    super.key,
    this.size = 64,
    this.radius = 14,
    this.tile = true,
  });

  final String videoId;
  final double size;
  final double radius;

  /// Without a cover: the outlined tile, or (false, in a mosaic) nothing.
  final bool tile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final file = ref.watch(artworkProvider(videoId)).value;
    final none = tile
        ? ThumbTile(size: size, radius: radius)
        : SizedBox.square(dimension: size);
    if (file == null) return none;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.file(
        file,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => none,
      ),
    );
  }
}

/// A playlist's cover: the one the user chose, else its first four tracks'
/// covers in a 2×2 grid (one cover when it has fewer), else the tile.
class PlaylistCover extends ConsumerWidget {
  const PlaylistCover(
    this.playlist, {
    super.key,
    this.size = 64,
    this.radius = 14,
  });

  final Playlist playlist;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chosen = playlist.coverPath;
    if (chosen != null && File(chosen).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(
          File(chosen),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => ThumbTile(size: size, radius: radius),
        ),
      );
    }
    final ids = [
      for (final t
          in ref.watch(playlistTracksProvider(playlist.id)).value ??
              const <Track>[])
        t.videoId,
    ].take(4).toList();
    if (ids.isEmpty) return ThumbTile(size: size, radius: radius);
    if (ids.length < 4) return TrackArt(ids.first, size: size, radius: radius);
    final half = size / 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: Wrap(
          children: [
            for (final id in ids)
              TrackArt(id, size: half, radius: 0, tile: false),
          ],
        ),
      ),
    );
  }
}

/// Lets the user pick an image from the phone; null if they don't.
Future<String?> _pickImage() async {
  final picked = await FilePicker.pickFiles(type: FileType.image);
  return picked.isEmpty ? null : picked.first.path;
}

void _deleteQuietly(String? path) {
  if (path == null) return;
  try {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  } on Object {
    // Tidied at the next launch.
  }
}

/// Long-press → Choose cover: a picture from the phone for [track].
Future<void> chooseTrackCover(WidgetRef ref, Track track) async {
  final path = await _pickImage();
  if (path == null) return;
  final kept = await ref
      .read(coversProvider)
      .keep(path, 'track-${track.videoId}');
  await ref.read(libraryProvider).setTrackCover(track.videoId, kept);
  _deleteQuietly(track.coverPath);
}

/// Back to YouTube's picture for [track].
Future<void> resetTrackCover(WidgetRef ref, Track track) async {
  await ref.read(libraryProvider).setTrackCover(track.videoId, null);
  _deleteQuietly(track.coverPath);
}

/// Choose cover: a picture from the phone for [playlist].
Future<void> choosePlaylistCover(WidgetRef ref, Playlist playlist) async {
  final path = await _pickImage();
  if (path == null) return;
  final kept = await ref
      .read(coversProvider)
      .keep(path, 'playlist-${playlist.id}');
  await ref.read(libraryProvider).setPlaylistCover(playlist.id, kept);
  _deleteQuietly(playlist.coverPath);
}

/// Back to the mosaic for [playlist].
Future<void> resetPlaylistCover(WidgetRef ref, Playlist playlist) async {
  await ref.read(libraryProvider).setPlaylistCover(playlist.id, null);
  _deleteQuietly(playlist.coverPath);
}

/// A playlist's "Remove downloads": stops keeping it offline and deletes
/// its cached tracks (not ones pinned on their own, kept by another offline
/// playlist, or playing now), after asking.
Future<void> confirmRemoveDownloads(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final library = ref.read(libraryProvider);
  final tracks = await library.playlistTracks(playlist.id);
  final entries = ref.read(cacheEntriesProvider).value ?? const {};
  final bytes = tracks.fold<int>(
    0,
    (sum, t) => sum + (entries[t.videoId]?.bytes ?? 0),
  );
  if (!context.mounted) return;
  await showVSheet<void>(
    context,
    title: 'Remove downloads',
    builder: (sheet) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Deletes up to ${formatBytes(bytes)} of "${playlist.title}" from '
          'this phone${playlist.pinned ? ' and stops keeping it offline' : ''}. '
          'Tracks pinned on their own or kept by another offline playlist '
          'stay. Anything removed streams (and caches) again next time.',
          style: VText.inter(14, height: 1.45),
        ),
        const SizedBox(height: 18),
        VButton.primary(
          'Remove',
          onPressed: () {
            Navigator.of(sheet).pop();
            unawaited(() async {
              if (playlist.pinned) {
                await library.setPlaylistPinned(playlist.id, false);
              }
              await ref
                  .read(cacheManagerProvider)
                  .removeAll(tracks.map((t) => t.videoId));
            }());
          },
        ),
        const SizedBox(height: 10),
        VButton.secondary('Keep', onPressed: () => Navigator.of(sheet).pop()),
      ],
    ),
  );
}

/// A page's parts in the desktop layout: [aside] (the cover, details and
/// actions) in a column on the left, [main] (the tracks) beside it.
/// Narrower, one under the other.
List<Widget> asideAndMain(
  BuildContext context, {
  required List<Widget> aside,
  required List<Widget> main,
}) {
  if (VLayout.of(context) != VLayout.desktop) return [...aside, ...main];
  Widget column(List<Widget> parts) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, w) in parts.indexed) ...[
        if (i > 0) const SizedBox(height: VSpace.cardGap),
        w,
      ],
    ],
  );
  // About a third for the aside, the rest for the tracks.
  return [
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 32, child: column(aside)),
        const Spacer(flex: 3),
        Expanded(flex: 65, child: column(main)),
      ],
    ),
  ];
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
      TrackCacheState.local => const VIconView(VIcon.phone, size: 18),
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
  TrackCacheState.local => localLabel,
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
          TrackArt(track.videoId, size: 44, radius: 10),
          const SizedBox(width: 12),
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
  double dock = shellMiniDock,
}) async {
  if (tracks.isEmpty) return;
  unawaited(context.push(Routes.player, extra: dock));
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
  final local = isLocal(track.videoId);
  final keptByPlaylist =
      !pinned &&
      (ref.read(pinnedIdsProvider).value?.contains(track.videoId) ?? false);
  final facts = [
    if (local) localLabel else 'Track',
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
                onTap: () =>
                    done(() => handler.playNext(track, source: source)),
              ),
              VListRow(
                leading: const VIconView(VIcon.queue),
                title: 'Add to queue',
                chevron: false,
                onTap: () =>
                    done(() => handler.addToQueue(track, source: source)),
              ),
              if (!local)
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
                  // Pinned by its playlist: the worker fetches it again.
                  subtitle: keptByPlaylist
                      ? 'Comes back: its playlist is kept offline'
                      : null,
                  chevron: false,
                  onTap: () => done(() async {
                    if (pinned) {
                      await library.setTrackPinned(track.videoId, false);
                    }
                    await cache.remove(track.videoId);
                  }),
                ),
              VListRow(
                leading: const VIconView(VIcon.image),
                title: 'Choose cover…',
                subtitle: 'A picture from your phone',
                chevron: false,
                onTap: () => done(() => chooseTrackCover(ref, track)),
              ),
              if (track.coverPath != null)
                VListRow(
                  leading: const VIconView(VIcon.image),
                  title: local
                      ? "Use the file's picture"
                      : "Use YouTube's picture",
                  chevron: false,
                  onTap: () => done(() => resetTrackCover(ref, track)),
                ),
              if (!local)
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
          PlaylistCover(s.playlist),
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
                  SizedBox(
                    width: double.infinity,
                    child: VBar(value: s.cachedCount / s.trackCount),
                  ),
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

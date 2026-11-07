import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_controls.dart';
import '../../core/widgets/v_list.dart';
import '../../core/widgets/v_page.dart';
import '../../core/widgets/v_progress.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/providers.dart';
import '../common.dart';

/// One playlist: play, shuffle, keep offline, and its tracks.
class PlaylistPage extends ConsumerWidget {
  const PlaylistPage({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref.watch(playlistProvider(id)).value;
    final tracks = ref.watch(playlistTracksProvider(id)).value ?? const [];
    final entries = ref.watch(cacheEntriesProvider).value ?? const {};
    final waiting = ref.watch(precacheWaitingProvider);
    if (playlist == null) {
      return const VDetailPage(backLabel: 'Library', title: '', children: []);
    }
    final total = tracks.fold<int>(0, (a, t) => a + t.durationMs);
    final cached = tracks
        .where((t) => entries[t.videoId]?.complete == true)
        .length;
    final synced = playlist.lastSyncedAt == null
        ? ''
        : ' · synced ${when(playlist.lastSyncedAt!)}';
    final offlineLine = cached >= tracks.length
        ? 'All ${tracks.length} cached'
        : '$cached of ${tracks.length} cached'
              '${playlist.pinned && waiting != null ? ' · $waiting' : ''}';

    return VDetailPage(
      backLabel: 'Library',
      title: playlist.title,
      onRefresh: () async => ref.read(syncOneProvider)(id),
      children: [
        Text(
          '${tracks.length} tracks · '
          '${totalLength(Duration(milliseconds: total))}$synced',
          style: VText.inter(13, weight: 300),
        ),
        Row(
          children: [
            Expanded(
              child: VButton.primary(
                'Play',
                enabled: tracks.isNotEmpty,
                onPressed: () =>
                    playTracks(context, ref, tracks, source: playlist.title),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: VButton.secondary(
                'Shuffle',
                enabled: tracks.isNotEmpty,
                onPressed: () => playTracks(
                  context,
                  ref,
                  tracks,
                  index: tracks.isEmpty
                      ? 0
                      : DateTime.now().microsecond % tracks.length,
                  source: playlist.title,
                  shuffle: true,
                ),
              ),
            ),
          ],
        ),
        VCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Available offline', style: VText.rowTitle),
                        const SizedBox(height: 3),
                        Text(offlineLine, style: VText.secondary),
                      ],
                    ),
                  ),
                  VSwitch(
                    value: playlist.pinned,
                    onChanged: (v) async {
                      await ref
                          .read(libraryProvider)
                          .setPlaylistPinned(id, v);
                      ref.read(cacheManagerProvider).kick();
                    },
                  ),
                ],
              ),
              if (playlist.pinned && tracks.isNotEmpty) ...[
                const SizedBox(height: 10),
                VBar(value: cached / tracks.length),
              ],
            ],
          ),
        ),
        if (tracks.isEmpty)
          const VFootnote('This playlist is empty on YouTube.')
        else
          VListSection(
            children: [
              for (final (i, t) in tracks.indexed)
                TrackRow(
                  track: t,
                  number: i + 1,
                  onTap: () => playTracks(
                    context,
                    ref,
                    tracks,
                    index: i,
                    source: playlist.title,
                  ),
                  onLongPress: () => showTrackActions(
                    context,
                    ref,
                    t,
                    source: playlist.title,
                  ),
                ),
            ],
          ),
        const VFootnote('Long-press a track for more.'),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/icons/v_icons.dart';
import '../../core/layout.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_controls.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_list.dart';
import '../../core/widgets/v_page.dart';
import '../../core/widgets/v_progress.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../common.dart';
import '../player/mini_player.dart';

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

    final mini = ref.watch(sessionProvider.select((s) => s.active));
    final bottom = MediaQuery.paddingOf(context).bottom;
    final page = VDetailPage(
      backLabel: 'Library',
      // Opened from the desktop sidebar there's no page behind: Library.
      onBack: () =>
          context.canPop() ? context.pop() : context.go(Routes.library),
      title: playlist.title,
      onRefresh: () async => ref.read(syncOneProvider)(id),
      children: asideAndMain(
        context,
        aside: [
          Row(
            children: [
              // Tap the cover to change it.
              VTappable(
                onTap: () => _coverActions(context, ref, playlist),
                child: PlaylistCover(playlist, size: 96, radius: 18),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  '${tracks.length} tracks · '
                  '${totalLength(Duration(milliseconds: total))}$synced',
                  style: VText.inter(13, weight: 300),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: VButton.primary(
                  'Play',
                  enabled: tracks.isNotEmpty,
                  onPressed: () => playTracks(
                    context,
                    ref,
                    tracks,
                    source: playlist.title,
                    dock: 12,
                  ),
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
                    dock: 12,
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
                if (cached > 0) ...[
                  const SizedBox(height: 12),
                  VButton.ghost(
                    'Remove downloads',
                    onPressed: () =>
                        confirmRemoveDownloads(context, ref, playlist),
                  ),
                ],
              ],
            ),
          ),
        ],
        main: [
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
                      dock: 12,
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
      ),
    );
    // On a desktop the now-playing bar is the window's own.
    if (!mini || VLayout.of(context).framed) return page;
    return Stack(
      children: [
        VBottomInset(extra: miniPlayerHeight + 12, child: page),
        Positioned(
          left: 0,
          right: 0,
          bottom: bottom + 12,
          child: const MiniPlayer(dock: 12),
        ),
      ],
    );
  }
}

/// The playlist's cover: choose a picture, or go back to the mosaic.
Future<void> _coverActions(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) => showVSheet<void>(
  context,
  title: 'Cover',
  builder: (sheet) {
    void done(Future<void> Function() action) {
      Navigator.of(sheet).pop();
      unawaited(action());
    }

    return VListSection(
      children: [
        VListRow(
          leading: const VIconView(VIcon.image),
          title: 'Choose cover…',
          subtitle: 'A picture from your phone',
          chevron: false,
          onTap: () => done(() => choosePlaylistCover(ref, playlist)),
        ),
        if (playlist.coverPath != null)
          VListRow(
            leading: const VIconView(VIcon.image),
            title: 'Use the mosaic',
            subtitle: "The first four tracks' covers",
            chevron: false,
            onTap: () => done(() => resetPlaylistCover(ref, playlist)),
          ),
      ],
    );
  },
);

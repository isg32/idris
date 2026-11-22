import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/icons/v_icons.dart';
import '../../core/layout.dart';
import '../../core/theme/v_text.dart';
import '../../core/theme/v_tokens.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_list.dart';
import '../../core/widgets/v_page.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../common.dart';
import '../../platform/local_music.dart';
import '../library/import_sheet.dart';
import '../settings/update.dart';

/// Home: what's playing, recently added, recently played, playlists.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider).value;
    final added = ref.watch(recentlyAddedProvider).value ?? const [];
    final played = ref.watch(recentlyPlayedProvider).value ?? const [];
    final lastSync = ref.watch(lastSyncProvider);

    Future<void> refresh() async {
      final r = await ref.read(syncProvider)();
      ref.read(lastSyncProvider.notifier).set(r);
    }

    final empty = playlists != null && playlists.isEmpty;
    final fresh = added.where((t) => t.isNew).length;
    final heading = SectionHeading(
      'Recently added',
      note: fresh == 0 ? null : '$fresh new',
    );
    final rest = <Widget>[
      if (played.isNotEmpty) ...[
        const SectionHeading('Recently played'),
        VListSection(
          padding: EdgeInsets.zero,
          children: [
            for (final p in played)
              TrackRow(
                track: p.track,
                subtitle: [
                  if (isLocal(p.track.videoId))
                    localLabel
                  else if (p.playlistTitle.isNotEmpty)
                    p.playlistTitle,
                  'played ${when(p.at)}',
                ].join(' · '),
                onTap: () => _playFromPlaylist(context, ref, p),
                onLongPress: () => showTrackActions(
                  context,
                  ref,
                  p.track,
                  source: p.playlistTitle,
                ),
              ),
          ],
        ),
      ],
      if (playlists != null && playlists.isNotEmpty) ...[
        const SectionHeading('Playlists'),
        for (final s in playlists) PlaylistCard(summary: s),
      ],
    ];
    return VTabPage(
      title: 'Idris',
      eyebrow: DateFormat('EEEE d MMMM').format(DateTime.now()).toUpperCase(),
      onRefresh: empty ? null : refresh,
      trailing: empty
          ? null
          : VCircleButton(icon: VIcon.sync, onTap: () => unawaited(refresh())),
      children: [
        const OfflineBanner(),
        // "Idris 1.1.0 is out", until it's closed.
        const UpdateCard(closable: true),
        if (empty) const _Empty(),
        if (lastSync != null && lastSync.added > 0)
          VFootnote('Synced · ${lastSync.added} new'),
        if (VLayout.of(context) == VLayout.desktop && added.isNotEmpty)
          // A window has room: Recently added down the left, the rest
          // beside it.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 30,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heading,
                    const SizedBox(height: VSpace.cardGap),
                    _AddedColumn(items: added),
                  ],
                ),
              ),
              const Spacer(flex: 3),
              Expanded(
                flex: 67,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final w in rest) ...[
                      w,
                      const SizedBox(height: VSpace.cardGap),
                    ],
                  ],
                ),
              ),
            ],
          )
        else ...[
          if (added.isNotEmpty) ...[heading, _AddedStrip(items: added)],
          ...rest,
        ],
      ],
    );
  }
}

/// Plays [item] with its playlist as the queue.
Future<void> _playFromPlaylist(
  BuildContext context,
  WidgetRef ref,
  TrackInPlaylist item,
) async {
  final local = isLocal(item.track.videoId);
  final tracks = local
      ? await ref.read(localMusicProvider).tracks()
      : item.playlistId == 0
      ? [item.track]
      : await ref.read(libraryProvider).playlistTracks(item.playlistId);
  final i = tracks.indexWhere((t) => t.videoId == item.track.videoId);
  if (!context.mounted) return;
  await playTracks(
    context,
    ref,
    i < 0 ? [item.track] : tracks,
    index: i < 0 ? 0 : i,
    source: local ? localLabel : item.playlistTitle,
  );
}

/// Recently added as a column (a desktop window's Home): cover, title and
/// length, one under another.
class _AddedColumn extends ConsumerWidget {
  const _AddedColumn({required this.items});

  final List<TrackInPlaylist> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          VTappable(
            onTap: () => _playFromPlaylist(context, ref, item),
            onLongPress: () => showTrackActions(
              context,
              ref,
              item.track,
              source: item.playlistTitle,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  TrackArt(item.track.videoId, size: 64, radius: 12),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.track.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: VText.inter(14, weight: 500, height: 1.25),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (item.isNew) 'New',
                            if (item.playlistTitle.isNotEmpty)
                              item.playlistTitle,
                            trackLength(item.track),
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
      ],
    );
  }
}

class _AddedStrip extends ConsumerWidget {
  const _AddedStrip({required this.items});

  final List<TrackInPlaylist> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 206,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: VSpace.cardGap),
        itemBuilder: (context, i) {
          final item = items[i];
          return VTappable(
            onTap: () => _playFromPlaylist(context, ref, item),
            onLongPress: () => showTrackActions(
              context,
              ref,
              item.track,
              source: item.playlistTitle,
            ),
            child: SizedBox(
              width: 132,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      TrackArt(
                        item.track.videoId,
                        size: 132,
                        radius: VRadius.card,
                      ),
                      if (item.isNew)
                        const Positioned(
                          top: 10,
                          left: 10,
                          child: VPill.badge('NEW'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.track.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: VText.inter(14, weight: 500, height: 1.25),
                  ),
                  const SizedBox(height: 4),
                  Text(trackLength(item.track), style: VText.doto(13)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: VCard(
        outline: VOutline.dashed,
        radius: VRadius.cardLarge,
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
        child: Column(
          children: [
            const VIconView(VIcon.wave, size: 40),
            const SizedBox(height: 14),
            Text('Nothing here yet', style: VText.doto(22)),
            const SizedBox(height: 10),
            Text(
              'Paste a YouTube playlist link. Only those videos play here, '
              'as audio.',
              textAlign: TextAlign.center,
              style: VText.inter(13, weight: 300, height: 1.5),
            ),
            const SizedBox(height: 20),
            Builder(
              builder: (context) => VButton.primary(
                'Import your first playlist',
                onPressed: () => showImportSheet(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

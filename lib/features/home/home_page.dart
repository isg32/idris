import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_text.dart';
import '../../core/theme/v_tokens.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_list.dart';
import '../../core/widgets/v_page.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../common.dart';
import '../library/import_sheet.dart';

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
    return VTabPage(
      title: 'Idris',
      eyebrow: DateFormat('EEEE d MMMM').format(DateTime.now()).toUpperCase(),
      onRefresh: empty ? null : refresh,
      trailing: empty
          ? null
          : VCircleButton(icon: VIcon.sync, onTap: () => unawaited(refresh())),
      children: [
        const OfflineBanner(),
        if (empty) const _Empty(),
        if (lastSync != null && lastSync.added > 0)
          VFootnote('Synced · ${lastSync.added} new'),
        if (added.isNotEmpty) ...[
          SectionHeading(
            'Recently added',
            note: added.where((t) => t.isNew).isEmpty
                ? null
                : '${added.where((t) => t.isNew).length} new',
          ),
          _AddedStrip(items: added),
        ],
        if (played.isNotEmpty) ...[
          const SectionHeading('Recently played'),
          VListSection(
            padding: EdgeInsets.zero,
            children: [
              for (final p in played)
                TrackRow(
                  track: p.track,
                  subtitle: [
                    if (p.playlistTitle.isNotEmpty) p.playlistTitle,
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
  final tracks = item.playlistId == 0
      ? [item.track]
      : await ref.read(libraryProvider).playlistTracks(item.playlistId);
  final i = tracks.indexWhere((t) => t.videoId == item.track.videoId);
  if (!context.mounted) return;
  await playTracks(
    context,
    ref,
    i < 0 ? [item.track] : tracks,
    index: i < 0 ? 0 : i,
    source: item.playlistTitle,
  );
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

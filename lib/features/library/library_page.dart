import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_controls.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_list.dart';
import '../../core/widgets/v_page.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../common.dart';
import 'import_sheet.dart';

/// Library: every playlist, or every track that plays offline.
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key, this.offline = false});

  final bool offline;

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  late bool _offline = widget.offline;

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(playlistsProvider).value ?? const [];
    final entries = ref.watch(cacheEntriesProvider).value ?? const {};
    final offlineCount = entries.values.where((e) => e.complete).length;
    return VTabPage(
      title: 'Library',
      trailing: VCircleButton(
        icon: VIcon.plus,
        filled: true,
        onTap: () => unawaited(showImportSheet(context)),
      ),
      onRefresh: () async {
        final r = await ref.read(syncProvider)();
        ref.read(lastSyncProvider.notifier).set(r);
      },
      header: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const OfflineBanner(),
            if (!(ref.watch(connectivityProvider).value ?? true))
              const SizedBox(height: 12),
            VSegmented<bool>(
              segments: {
                false: 'All · ${playlists.length}',
                true: 'Offline · $offlineCount',
              },
              value: _offline,
              onChanged: (v) => setState(() => _offline = v),
            ),
          ],
        ),
      ),
      children: _offline
          ? const [_OfflineTracks()]
          : [
              if (playlists.isEmpty)
                const VFootnote(
                  'No playlists yet. Tap + and paste a YouTube playlist link.',
                ),
              for (final s in playlists)
                PlaylistCard(
                  summary: s,
                  onLongPress: () => showPlaylistActions(context, ref, s),
                ),
              if (playlists.isNotEmpty)
                const VFootnote(
                  'Long-press a playlist to pin it offline, sync now, rename '
                  'or remove.',
                ),
            ],
    );
  }
}

/// Cached tracks, pinned first, then auto-cached by last play.
class _OfflineTracks extends ConsumerWidget {
  const _OfflineTracks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(cacheEntriesProvider).value ?? const {};
    final pinned = ref.watch(pinnedIdsProvider).value ?? const <String>{};
    final settings = ref.watch(settingsProvider).value ?? const Settings();
    final storage = ref.watch(storageProvider);
    return FutureBuilder<List<Track>>(
      future: _tracks(ref, entries.values.where((e) => e.complete)),
      builder: (context, snap) {
        final tracks = snap.data ?? const [];
        final p = [
          for (final t in tracks)
            if (pinned.contains(t.videoId)) t,
        ];
        final a = [
          for (final t in tracks)
            if (!pinned.contains(t.videoId)) t,
        ]..sort(
            (x, y) => _last(entries[y.videoId]).compareTo(
              _last(entries[x.videoId]),
            ),
          );
        if (tracks.isEmpty) {
          return const VFootnote(
            'Nothing cached yet. Tracks you play are kept here, and pinned '
            'playlists download ahead.',
          );
        }
        Widget list(List<Track> ts) => VListSection(
          children: [
            for (final (i, t) in ts.indexed)
              TrackRow(
                track: t,
                subtitle: entries[t.videoId]?.lastPlayedAt == null
                    ? 'Not played yet'
                    : 'Played ${when(entries[t.videoId]!.lastPlayedAt!)}',
                onTap: () => playTracks(
                  context,
                  ref,
                  ts,
                  index: i,
                  source: 'Offline',
                ),
                onLongPress: () =>
                    showTrackActions(context, ref, t, source: 'Offline'),
              ),
          ],
        );
        final limit = settings.cacheLimitGb == 0
            ? ''
            : ' of ${settings.cacheLimitGb} GB';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (p.isNotEmpty) ...[
              SectionHeading(
                'Pinned · ${p.length}',
                note: formatBytes(storage.pinned),
              ),
              const SizedBox(height: 12),
              list(p),
              const SizedBox(height: 12),
            ],
            if (a.isNotEmpty) ...[
              SectionHeading(
                'Auto-cached · ${a.length}',
                note: '${formatBytes(storage.auto)}$limit',
              ),
              const SizedBox(height: 12),
              list(a),
            ],
          ],
        );
      },
    );
  }

  static DateTime _last(CacheEntry? e) =>
      e?.lastPlayedAt ?? e?.cachedAt ?? DateTime(2000);

  static Future<List<Track>> _tracks(
    WidgetRef ref,
    Iterable<CacheEntry> entries,
  ) async {
    final library = ref.read(libraryProvider);
    final out = <Track>[];
    for (final e in entries) {
      final t = await library.track(e.videoId);
      if (t != null) out.add(t);
    }
    return out;
  }
}

/// Long-press on a playlist: pin offline, sync now, rename, remove.
Future<void> showPlaylistActions(
  BuildContext context,
  WidgetRef ref,
  PlaylistSummary s,
) {
  final library = ref.read(libraryProvider);
  return showVSheet<void>(
    context,
    title: s.title,
    builder: (sheet) {
      void done(FutureOr<void> Function() action) {
        Navigator.of(sheet).pop();
        unawaited(Future.sync(action));
      }

      return VListSection(
        children: [
          VListRow(
            leading: const VIconView(VIcon.pin),
            title: s.pinned ? 'Stop keeping offline' : 'Pin offline',
            subtitle: s.pinned ? null : 'Downloads every track and keeps it',
            chevron: false,
            onTap: () => done(() async {
              await library.setPlaylistPinned(s.id, !s.pinned);
              ref.read(cacheManagerProvider).kick();
            }),
          ),
          VListRow(
            leading: const VIconView(VIcon.sync),
            title: 'Sync now',
            chevron: false,
            onTap: () => done(() => ref.read(syncOneProvider)(s.id)),
          ),
          VListRow(
            leading: const VIconView(VIcon.playNext),
            title: 'Rename',
            chevron: false,
            onTap: () => done(() => _rename(context, ref, s)),
          ),
          VListRow(
            leading: const VIconView(VIcon.trash),
            title: 'Remove from Idris',
            subtitle: 'Stays on YouTube',
            chevron: false,
            onTap: () => done(() => library.removePlaylist(s.id)),
          ),
        ],
      );
    },
  );
}

Future<void> _rename(
  BuildContext context,
  WidgetRef ref,
  PlaylistSummary s,
) async {
  final controller = TextEditingController(text: s.title);
  await showVSheet<void>(
    context,
    title: 'Rename',
    builder: (sheet) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VTextField(controller: controller, autofocus: true),
        const SizedBox(height: 16),
        VButton.primary(
          'Save',
          onPressed: () {
            final name = controller.text.trim();
            if (name.isNotEmpty) {
              unawaited(ref.read(libraryProvider).renamePlaylist(s.id, name));
            }
            Navigator.of(sheet).pop();
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Only in Idris. The playlist keeps its name on YouTube.',
          style: VText.secondary,
        ),
      ],
    ),
  );
  controller.dispose();
}

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/v_icons.dart';
import '../../core/layout.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_list.dart';
import '../../core/widgets/v_page.dart';
import '../../core/widgets/v_progress.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../platform/local_music.dart';
import '../common.dart';
import '../player/mini_player.dart';

String get _source => localLabel;

/// "On this phone": the songs in the folders the user chose, and the
/// folders themselves.
class LocalPage extends ConsumerStatefulWidget {
  const LocalPage({super.key});

  @override
  ConsumerState<LocalPage> createState() => _LocalPageState();
}

class _LocalPageState extends ConsumerState<LocalPage> {
  bool _reading = false;

  /// Runs [work] (adding or reading folders) with a spinner showing.
  Future<void> _busy(Future<void> Function() work) async {
    if (_reading) return;
    setState(() => _reading = true);
    try {
      await work();
    } on Object catch (e) {
      debugPrint('Reading folders failed: $e');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracks = ref.watch(localTracksProvider).value ?? const <Track>[];
    final folders = ref.watch(localFoldersProvider).value ?? const [];
    final counts = ref.watch(localCountsProvider).value ?? const {};
    final music = ref.read(localMusicProvider);
    final total = tracks.fold<int>(0, (a, t) => a + t.durationMs);
    final mini = ref.watch(sessionProvider.select((s) => s.active));
    final bottom = MediaQuery.paddingOf(context).bottom;

    final page = VDetailPage(
      backLabel: 'Library',
      title: _source,
      onRefresh: () => _busy(music.scanAll),
      children: [
        Text(
          tracks.isEmpty
              ? 'Music from folders on this phone'
              : '${tracks.length} songs · '
                    '${totalLength(Duration(milliseconds: total))}',
          style: VText.inter(13, weight: 300),
        ),
        if (tracks.isNotEmpty)
          Row(
            children: [
              Expanded(
                child: VButton.primary(
                  'Play',
                  onPressed: () => playTracks(
                    context,
                    ref,
                    tracks,
                    source: _source,
                    dock: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: VButton.secondary(
                  'Shuffle',
                  onPressed: () => playTracks(
                    context,
                    ref,
                    tracks,
                    index: DateTime.now().microsecond % tracks.length,
                    source: _source,
                    dock: 12,
                    shuffle: true,
                  ),
                ),
              ),
            ],
          ),
        const SectionHeading('Folders'),
        VListSection(
          children: [
            for (final f in folders)
              VListRow(
                leading: const VIconView(VIcon.folder),
                title: f.name,
                subtitle: '${counts[f.uri] ?? 0} songs',
                onTap: () => _folderActions(context, f),
              ),
            VListRow(
              leading: _reading
                  ? const VSpinner(size: 20)
                  : const VIconView(VIcon.plus),
              title: _reading ? 'Reading…' : 'Add a folder',
              subtitle: folders.isEmpty
                  ? 'Idris plays every audio file in it'
                  : null,
              chevron: false,
              onTap: _reading ? null : () => _busy(music.addFolder),
            ),
          ],
        ),
        if (folders.isNotEmpty && tracks.isEmpty && !_reading)
          const VFootnote('No audio files in these folders yet.'),
        if (tracks.isNotEmpty)
          VListSection(
            children: [
              for (final (i, t) in tracks.indexed)
                TrackRow(
                  track: t,
                  number: i + 1,
                  subtitle: t.channel.isEmpty ? null : t.channel,
                  onTap: () => playTracks(
                    context,
                    ref,
                    tracks,
                    index: i,
                    source: _source,
                    dock: 12,
                  ),
                  onLongPress: () =>
                      showTrackActions(context, ref, t, source: _source),
                ),
            ],
          ),
        const VFootnote(
          'Pull down to pick up new files. Removing a folder only takes it '
          'out of Idris; the files stay where they are.',
        ),
      ],
    );
    // On a desktop the now-playing bar is the window's own.
    if (!mini || desktopLayout) return page;
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

  /// A folder: read it again, or take it out of Idris.
  Future<void> _folderActions(BuildContext context, LocalFolder folder) =>
      showVSheet<void>(
        context,
        title: folder.name,
        builder: (sheet) {
          void done(Future<void> Function() action) {
            Navigator.of(sheet).pop();
            unawaited(action());
          }

          final music = ref.read(localMusicProvider);
          return VListSection(
            children: [
              VListRow(
                leading: const VIconView(VIcon.sync),
                title: 'Read again',
                subtitle: 'Picks up new and changed files',
                chevron: false,
                onTap: () =>
                    done(() => _busy(() async => music.scan(folder.uri))),
              ),
              VListRow(
                leading: const VIconView(VIcon.trash),
                title: 'Remove from Idris',
                subtitle: 'The files stay on the phone',
                chevron: false,
                onTap: () => done(() => music.removeFolder(folder.uri)),
              ),
            ],
          );
        },
      );
}

/// Library's entry for "On this phone".
class LocalCard extends ConsumerWidget {
  const LocalCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(localTracksProvider).value ?? const <Track>[];
    return VCard(
      onTap: onTap,
      child: Row(
        children: [
          tracks.length >= 4
              ? _Mosaic([for (final t in tracks.take(4)) t.videoId])
              : const ThumbTile(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_source, style: VText.doto(20)),
                const SizedBox(height: 4),
                Text(
                  tracks.isEmpty
                      ? 'Add a folder of music'
                      : '${tracks.length} songs',
                  style: VText.secondary,
                ),
              ],
            ),
          ),
          const VIconView(VIcon.phone, size: 18),
        ],
      ),
    );
  }
}

class _Mosaic extends StatelessWidget {
  const _Mosaic(this.ids);
  final List<String> ids;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: SizedBox.square(
      dimension: 64,
      child: Wrap(
        children: [
          for (final id in ids) TrackArt(id, size: 32, radius: 0, tile: false),
        ],
      ),
    ),
  );
}

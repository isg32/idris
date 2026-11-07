import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_controls.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_list.dart';
import '../../core/widgets/v_page.dart';
import '../../core/widgets/v_progress.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../platform/quality.dart';
import '../../platform/youtube.dart';
import '../common.dart';

/// Settings: quality, cache, Glyph, library, about.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value ?? const Settings();
    final storage = ref.watch(storageProvider);
    final glyph = ref.watch(glyphAvailableProvider).value ?? false;
    final library = ref.read(libraryProvider);
    void set(String key, String value) => unawaited(library.setPref(key, value));

    final used = storage.pinned + storage.auto;
    final limitBytes = s.cacheLimitBytes;
    final barMax = limitBytes == null ? used : storage.pinned + limitBytes;

    return VTabPage(
      title: 'Settings',
      children: [
        const SectionHeading('Playback'),
        VListSection(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Audio quality', style: VText.rowTitle),
                  const SizedBox(height: 10),
                  VSegmented<AudioQuality>(
                    segments: {
                      for (final q in AudioQuality.values) q: q.label,
                    },
                    value: s.quality,
                    onChanged: (q) => set('quality', q.name),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${s.quality.hint} Cached tracks keep the quality they '
                    'were saved at.',
                    style: VText.secondary,
                  ),
                ],
              ),
            ),
            VListRow(
              title: 'When a repeat count ends',
              subtitle: 'Default for new counts',
              trailing: VSegmented<RepeatEnd>(
                compact: true,
                segments: const {RepeatEnd.stop: 'Stop', RepeatEnd.next: 'Next'},
                value: s.repeatEnd,
                onChanged: (v) => set('repeatEnd', v.name),
              ),
            ),
          ],
        ),

        const SectionHeading('Offline and cache'),
        VListSection(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text('Storage used', style: VText.rowTitle),
                      ),
                      Text(formatBytes(used), style: VText.doto(22)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _StorageBar(
                    pinned: barMax == 0 ? 0 : storage.pinned / barMax,
                    auto: barMax == 0 ? 0 : storage.auto / barMax,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      _Legend(
                        filled: true,
                        text: 'Pinned ${formatBytes(storage.pinned)}',
                      ),
                      _Legend(
                        filled: false,
                        text:
                            'Auto ${formatBytes(storage.auto)}'
                            '${limitBytes == null ? '' : ' of ${s.cacheLimitGb} GB'}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            VListRow(
              title: 'Cache limit',
              subtitle: 'Oldest unpinned tracks go first',
              trailing: _LimitStepper(
                gb: s.cacheLimitGb,
                onChanged: (gb) async {
                  await library.setPref('cacheLimitGb', '$gb');
                  await ref.read(cacheManagerProvider).evict();
                },
              ),
            ),
            VListRow(
              title: 'Pre-cache on Wi-Fi only',
              subtitle: 'Tracks you play are always cached',
              trailing: VSwitch(
                value: s.precacheWifiOnly,
                onChanged: (v) async {
                  await library.setPref('precacheWifiOnly', '$v');
                  ref.read(cacheManagerProvider).kick();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: VButton.ghost(
                'Clear auto cache · ${formatBytes(storage.auto)}',
                enabled: storage.auto > 0,
                onPressed: () => _confirmClear(context, ref, storage.auto),
              ),
            ),
          ],
        ),

        if (glyph) ...[
          const SectionHeading('Glyph'),
          VListSection(
            children: [
              VListRow(
                title: 'Breathe while playing',
                subtitle:
                    'A slow glyph pulse on the back while Idris is open. '
                    'Needs Glyph debug mode, as in Veronica.',
                trailing: VSwitch(
                  value: s.glyph,
                  onChanged: (v) => set('glyph', '$v'),
                ),
              ),
            ],
          ),
        ],

        const SectionHeading('Library'),
        VListSection(
          children: [
            VListRow(
              title: 'Sync when the app opens',
              trailing: VSwitch(
                value: s.syncOnOpen,
                onChanged: (v) => set('syncOnOpen', '$v'),
              ),
            ),
            VListRow(
              title: 'Export library',
              subtitle: 'Playlists as JSON',
              onTap: () => _export(context, ref),
            ),
            VListRow(
              title: 'Import library',
              subtitle: 'Adds playlists from a file',
              onTap: () => _import(context, ref),
            ),
          ],
        ),

        const SectionHeading('About'),
        const VListSection(
          children: [VListRow(title: 'Idris', value: '1.0.0')],
        ),
        const VFootnote(
          'Audio from your own YouTube playlists — nothing else. '
          'Doto and Inter (OFL), NewPipe Extractor (GPL-3.0), '
          'youtube_explode_dart (BSD-3), just_audio and audio_service (MIT).',
        ),
      ],
    );
  }
}

class _StorageBar extends StatelessWidget {
  const _StorageBar({required this.pinned, required this.auto});

  final double pinned;
  final double auto;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final ink = VInk.of(context);
        final w = c.maxWidth;
        final p = (pinned.clamp(0, 1)) * w;
        final a = (auto.clamp(0, 1 - pinned.clamp(0, 1))) * w;
        return Container(
          height: 6,
          decoration: BoxDecoration(
            border: Border.all(color: ink),
            borderRadius: BorderRadius.circular(3),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Row(
              children: [
                SizedBox(width: p, child: ColoredBox(color: ink)),
                SizedBox(
                  width: a,
                  child: VHatched(width: a, height: 6),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.filled, required this.text});

  final bool filled;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: filled ? ink : null,
            border: Border.all(color: ink),
            borderRadius: BorderRadius.circular(2),
          ),
          child: filled
              ? null
              : const ClipRRect(child: VHatched(width: 10, height: 10)),
        ),
        const SizedBox(width: 6),
        Text(text, style: VText.secondary),
      ],
    );
  }
}

class _LimitStepper extends StatelessWidget {
  const _LimitStepper({required this.gb, required this.onChanged});

  final int gb;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const steps = Settings.cacheLimitSteps;
    final i = steps.contains(gb) ? steps.indexOf(gb) : 2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        VCircleButton(
          icon: VIcon.minus,
          size: 30,
          onTap: i == 0 ? null : () => onChanged(steps[i - 1]),
        ),
        SizedBox(
          width: 72,
          child: Text(
            gb == 0 ? 'No limit' : '$gb GB',
            textAlign: TextAlign.center,
            style: VText.doto(gb == 0 ? 14 : 18),
          ),
        ),
        VCircleButton(
          icon: VIcon.plus,
          size: 30,
          onTap: i == steps.length - 1 ? null : () => onChanged(steps[i + 1]),
        ),
      ],
    );
  }
}

Future<void> _confirmClear(BuildContext context, WidgetRef ref, int bytes) =>
    showVSheet<void>(
      context,
      title: 'Clear auto cache',
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Removes ${formatBytes(bytes)} of tracks you played. Pinned '
            'tracks stay. Anything removed streams (and caches) again next '
            'time.',
            style: VText.inter(14, height: 1.45),
          ),
          const SizedBox(height: 18),
          VButton.primary(
            'Clear',
            onPressed: () {
              unawaited(ref.read(cacheManagerProvider).clearAuto());
              Navigator.of(sheet).pop();
            },
          ),
          const SizedBox(height: 10),
          VButton.secondary(
            'Keep',
            onPressed: () => Navigator.of(sheet).pop(),
          ),
        ],
      ),
    );

Future<void> _export(BuildContext context, WidgetRef ref) async {
  final json = await ref.read(libraryProvider).exportJson();
  try {
    final path = await FilePicker.saveFile(
      dialogTitle: 'Export library',
      fileName: 'idris-library.json',
      mimeType: 'application/json',
      bytes: utf8.encode(json),
    );
    if (path == null) return;
  } on Object {
    await Clipboard.setData(ClipboardData(text: json));
  }
}

Future<void> _import(BuildContext context, WidgetRef ref) async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  final path = picked.isEmpty ? null : picked.first.path;
  if (path == null) return;
  final library = ref.read(libraryProvider);
  try {
    final items = Library.parseExport(await File(path).readAsString());
    for (final item in items) {
      try {
        final id = await library.importPlaylist(await fetchPlaylist(item.id));
        if (item.pinned) await library.setPlaylistPinned(id, true);
      } on Object catch (e) {
        debugPrint('Import of ${item.id} failed: $e');
      }
    }
    await library.setPref('onboarded', 'true');
    ref.read(cacheManagerProvider).kick();
  } on FormatException catch (e) {
    if (!context.mounted) return;
    await showVSheet<void>(
      context,
      title: 'Import library',
      builder: (_) => Text(e.message, style: VText.body),
    );
  }
}

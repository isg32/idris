import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/providers.dart';
import '../../platform/youtube.dart';
import '../common.dart';

/// Opens the import sheet; after an import, opens the playlist.
Future<void> showImportSheet(BuildContext context) async {
  final id = await showVSheet<int>(
    context,
    title: 'Import playlist',
    builder: (_) => const ImportForm(),
  );
  if (id != null && context.mounted) {
    unawaited(context.push(Routes.playlist(id)));
  }
}

/// Paste a link → preview → add. Pops with the playlist's ID.
class ImportForm extends ConsumerStatefulWidget {
  const ImportForm({super.key, this.onImported});

  /// Called instead of popping (onboarding).
  final ValueChanged<int>? onImported;

  @override
  ConsumerState<ImportForm> createState() => _ImportFormState();
}

class _ImportFormState extends ConsumerState<ImportForm> {
  final _link = TextEditingController();
  bool _busy = false;
  String? _error;
  YtPlaylist? _preview;
  int? _existingId;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _link.text = text;
    await _fetch();
  }

  Future<void> _fetch() async {
    final text = _link.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
      _existingId = null;
    });
    try {
      final id = parsePlaylistId(text);
      if (id == null) throw PlaylistError.notAPlaylist;
      final existing = await ref.read(libraryProvider).byYtId(id);
      final p = await fetchPlaylist(id);
      if (!mounted) return;
      setState(() {
        _preview = p;
        _existingId = existing?.id;
      });
    } on PlaylistError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Couldn\'t fetch it: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final p = _preview;
    if (p == null) return;
    setState(() => _busy = true);
    final id = await ref.read(libraryProvider).importPlaylist(p);
    await ref.read(libraryProvider).setPref('onboarded', 'true');
    if (!mounted) return;
    if (widget.onImported != null) {
      widget.onImported!(id);
    } else {
      Navigator.of(context).pop(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: VTextField(
                controller: _link,
                placeholder: 'youtube.com/playlist?list=…',
                style: VText.inter(14),
                onSubmitted: (_) => _fetch(),
              ),
            ),
            const SizedBox(width: 8),
            VPill('Paste', onTap: _busy ? null : _paste),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Public or unlisted playlists. No sign-in.',
          style: VText.secondary,
        ),
        const SizedBox(height: 16),
        if (_busy && p == null)
          const VCard(
            outline: VOutline.dashed,
            child: Row(
              children: [
                CupertinoActivityIndicator(),
                SizedBox(width: 12),
                Text('Fetching the playlist…'),
              ],
            ),
          ),
        if (_error != null)
          VCard(
            outline: VOutline.dashed,
            child: Text(_error!, style: VText.inter(14, weight: 500)),
          ),
        if (p != null) ...[
          VCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.title, style: VText.doto(22)),
                const SizedBox(height: 4),
                Text(
                  '${p.videos.length} videos · '
                  '${totalLength(p.videos.fold(Duration.zero, (a, v) => a + v.duration))}'
                  '${p.channel.isEmpty ? '' : ' · ${p.channel}'}',
                  style: VText.secondary,
                ),
                const SizedBox(height: 10),
                for (final v in p.videos.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      v.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VText.body,
                    ),
                  ),
                if (p.videos.length > 3)
                  Text(
                    'and ${p.videos.length - 3} more',
                    style: VText.secondary,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_existingId != null) ...[
            Text(
              'Already in your library.',
              style: VText.inter(13, weight: 500),
            ),
            const SizedBox(height: 10),
            VButton.primary(
              'Open',
              onPressed: () {
                if (widget.onImported != null) {
                  widget.onImported!(_existingId!);
                } else {
                  Navigator.of(context).pop(_existingId);
                }
              },
            ),
          ] else
            VButton.primary(
              'Add ${p.videos.length} tracks',
              enabled: !_busy && p.videos.isNotEmpty,
              onPressed: _add,
            ),
        ] else
          VButton.primary('Fetch', enabled: !_busy, onPressed: _fetch),
      ],
    );
  }
}

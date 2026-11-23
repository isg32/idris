import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/v_colors.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../data/providers.dart';
import '../../platform/audio_handler.dart';
import '../../platform/lyrics.dart';

/// A track's lyrics in the player. Synced lyrics follow the song: the line
/// being sung is ink, the rest faded, and it's kept in view; tap a line to
/// go to it. Plain lyrics just scroll.
class LyricsView extends ConsumerStatefulWidget {
  const LyricsView(this.videoId, {super.key, this.edgeBlur = false});

  final String videoId;

  /// Lines blur as they scroll in at the bottom and out at the top (the
  /// phone's player), on top of fading.
  final bool edgeBlur;

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  final _scroll = ScrollController();
  List<GlobalKey> _keys = const [];
  int _shown = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Brings line [i] to a little above the middle.
  void _follow(int i) {
    if (i == _shown || i < 0 || i >= _keys.length) return;
    _shown = i;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _keys[i].currentContext;
      if (c == null || !c.mounted) return;
      unawaited(
        Scrollable.ensureVisible(
          c,
          alignment: 0.38,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final found = ref.watch(lyricsProvider(widget.videoId));
    return found.when(
      loading: () => const _Note('Finding lyrics…'),
      error: (_, _) => const _Note('No lyrics found for this one.'),
      data: (lyrics) {
        if (lyrics == null || lyrics.lines.isEmpty) {
          return const _Note('No lyrics found for this one.');
        }
        return _lines(context, lyrics);
      },
    );
  }

  Widget _lines(BuildContext context, Lyrics lyrics) {
    if (_keys.length != lyrics.lines.length) {
      _keys = [for (final _ in lyrics.lines) GlobalKey()];
      _shown = -1;
    }
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final now = lyrics.lineAt(pos);
    if (lyrics.synced) _follow(now);
    final handler = ref.read(audioHandlerProvider);
    // Room before the first line and after the last, as shares of the
    // space ([height]), so the line being sung is never in a blurred or
    // faded edge: the first starts below the top's blur, and the last can
    // scroll up to where lines are followed.
    Widget scrolling(double height) => SingleChildScrollView(
      controller: _scroll,
      padding: widget.edgeBlur
          ? EdgeInsets.only(top: height * 0.3, bottom: height * 0.55)
          : const EdgeInsets.symmetric(vertical: 40),
      child: _column(lyrics, now, handler),
    );
    final list = scrolling(0);
    final faded = ShaderMask(
      // Lines fade in and out at the top and bottom edges.
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        // A mask: only the alpha counts (dstIn), so black means "shown".
        colors: [
          VColors.transparent,
          VColors.black,
          VColors.black,
          VColors.transparent,
        ],
        stops: [0, 0.05, 0.95, 1],
      ).createShader(r),
      blendMode: BlendMode.dstIn,
      child: list,
    );
    if (!widget.edgeBlur) return faded;
    // Lines soften as they come in at the bottom and leave at the top (a
    // gentle progressive blur over about a fifth of the space), and fade
    // out at the very edge, so the strongest blur, where its samples would
    // show as grain, is never seen.
    return LayoutBuilder(
      builder: (context, c) => ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // A mask: only the alpha counts (dstIn), so black means "shown".
          colors: [
            VColors.transparent,
            VColors.black,
            VColors.black,
            VColors.transparent,
          ],
          stops: [0, 0.12, 0.88, 1],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: VBlurredEdges(
          top: c.maxHeight * 0.2,
          bottom: c.maxHeight * 0.2,
          maxRadius: 7,
          // The blur's edges are the area's, not the first and last lines'.
          child: ColoredBox(
            color: VColors.unseen,
            child: SizedBox.expand(child: scrolling(c.maxHeight)),
          ),
        ),
      ),
    );
  }

  /// The lines, then where they came from.
  Widget _column(Lyrics lyrics, int now, IdrisAudioHandler handler) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, line) in lyrics.lines.indexed)
        _Line(
          key: _keys[i],
          text: line.text,
          synced: lyrics.synced,
          now: i == now,
          past: i < now,
          onTap: line.at == null
              ? null
              : () => unawaited(handler.seek(line.at!)),
        ),
      const SizedBox(height: 24),
      Text(
        lyrics.source == 'file'
            ? 'Lyrics from the .lrc beside this file'
            : 'Lyrics from LRCLIB',
        style: VText.secondary,
      ),
    ],
  );
}

class _Line extends StatelessWidget {
  const _Line({
    super.key,
    required this.text,
    required this.synced,
    required this.now,
    required this.past,
    this.onTap,
  });

  final String text;
  final bool synced;
  final bool now;
  final bool past;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // An instrumental gap in synced lyrics: a quiet "♪".
    final words = text.isEmpty && synced ? '♪' : text;
    final style = synced
        ? VText.inter(22, weight: now ? 600 : 400, height: 1.3)
        : VText.inter(16, weight: 400, height: 1.5);
    final line = Padding(
      padding: EdgeInsets.symmetric(vertical: synced ? 8 : 1),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: !synced || now ? 1 : (past ? 0.32 : 0.48),
        child: Text(words, style: style),
      ),
    );
    return onTap == null
        ? line
        : VTappable(haptic: false, onTap: onTap, child: line);
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Center(child: Text(text, style: VText.inter(15, weight: 300)));
}

import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/v_ink.dart';
import 'mini_player.dart';

/// How far above the bottom safe area the mini player sits on tab pages
/// (above the floating tab bar); detail pages pass their own.
const double shellMiniDock = 22 + 62 + 10;

/// The full player as a panel that grows out of the mini player and,
/// swiped down, shrinks back into it (as in Spotify and Apple Music).
///
/// The route underneath stays visible, so the mini player is there when
/// the panel lands on it. Back and the system back gesture shrink it too.
class PlayerSheet extends StatefulWidget {
  const PlayerSheet({
    super.key,
    required this.child,
    this.dock = shellMiniDock,
  });

  final Widget child;

  /// Where the mini player is: its distance above the bottom safe area.
  final double dock;

  /// Shrinks the panel into the mini player and closes it.
  static Future<void> close(BuildContext context) =>
      context.findAncestorStateOfType<_PlayerSheetState>()?._close() ??
      Future.value();

  @override
  State<PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends State<PlayerSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 340),
  );
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open.forward());
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    await _open.animateBack(0, curve: Curves.easeInCubic);
    if (mounted) Navigator.of(context).pop();
  }

  void _drag(DragUpdateDetails d) {
    final h = MediaQuery.sizeOf(context).height;
    _open.value -= d.primaryDelta! / (h * 0.8);
  }

  void _release(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v > 700 || (_open.value < 0.75 && v >= 0)) {
      HapticFeedback.lightImpact();
      unawaited(_close());
    } else {
      unawaited(_open.forward());
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final full = Offset.zero & size;
    final mini = Rect.fromLTWH(
      12,
      size.height - pad.bottom - widget.dock - miniPlayerHeight,
      size.width - 24,
      miniPlayerHeight,
    );
    final paper = VInk.surfaceOf(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: _drag,
        onVerticalDragEnd: _release,
        child: AnimatedBuilder(
          animation: _open,
          builder: (context, child) {
            final t = Curves.easeOutCubic.transform(_open.value);
            final rect = Rect.lerp(mini, full, t)!;
            final radius = lerpDouble(20, 0, t)!;
            // The page fades in once the panel has some room, and the
            // panel itself fades out as it lands on the mini player.
            final content = ((t - 0.35) / 0.65).clamp(0.0, 1.0);
            final panel = (t / 0.2).clamp(0.0, 1.0);
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: rect,
                  child: Opacity(
                    opacity: panel,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: ColoredBox(
                        color: paper,
                        child: OverflowBox(
                          alignment: Alignment.topCenter,
                          minWidth: size.width,
                          maxWidth: size.width,
                          minHeight: size.height,
                          maxHeight: size.height,
                          child: Opacity(opacity: content, child: child),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}

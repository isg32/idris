import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/icons/v_icons.dart';
import '../core/widgets/v_ink.dart';
import '../core/theme/v_text.dart';
import '../core/theme/v_tokens.dart';
import '../core/widgets/v_glass.dart';
import '../core/widgets/v_page.dart';
import '../data/providers.dart';
import '../features/player/mini_player.dart';

/// The three tabs with the floating glass tab bar over them.
///
/// Back on any tab goes to Home. Back on Home shows "Swipe back again to
/// exit"; a second back within [exitWindow] closes the app.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const tabs = [
    VTabItem('Home', VIcon.home),
    VTabItem('Library', VIcon.library),
    VTabItem('Settings', VIcon.gear),
  ];

  static const exitWindow = Duration(seconds: 2);

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  DateTime? _lastBack;
  bool _showExitHint = false;
  Timer? _hintTimer;

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  void _onBack() {
    final shell = widget.shell;
    if (shell.currentIndex != 0) {
      shell.goBranch(0);
      return;
    }
    final now = DateTime.now();
    if (_lastBack != null && now.difference(_lastBack!) < AppShell.exitWindow) {
      SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    HapticFeedback.selectionClick();
    setState(() => _showExitHint = true);
    _hintTimer?.cancel();
    _hintTimer = Timer(AppShell.exitWindow, () {
      if (mounted) setState(() => _showExitHint = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Consumer(
      builder: (context, ref, _) {
        final mini = ref.watch(sessionProvider.select((s) => s.active));
        return _build(shell, bottom, mini ? miniPlayerHeight + 10 : 0.0);
      },
    );
  }

  Widget _build(StatefulNavigationShell shell, double bottom, double mini) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: VBottomInset(extra: mini, child: shell),
          ),
          // Content scrolling under the floating tab bar softens into a blur
          // that is strongest at the bottom edge.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VEdgeBlur(
              edge: VEdge.bottom,
              solid: bottom + 22 + 62 + mini,
              fade: 32,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottom + 22 + 62 + 12 + mini,
            child: IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  opacity: _showExitHint ? 1 : 0,
                  duration: VMotion.standard,
                  curve: VMotion.curve,
                  child: VGlass(
                    radius: VRadius.pill,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Text(
                        'Swipe back again to exit',
                        style: VText.inter(
                          13,
                          weight: 500,
                        ).copyWith(color: VInk.of(context)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (mini > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottom + 22 + 62 + 10,
              child: const MiniPlayer(),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottom,
            child: VTabBar(
              items: AppShell.tabs,
              index: shell.currentIndex,
              onTap: (i) =>
                  shell.goBranch(i, initialLocation: i == shell.currentIndex),
            ),
          ),
        ],
      ),
    );
  }
}

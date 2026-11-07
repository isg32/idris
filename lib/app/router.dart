import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/v_tokens.dart';
import '../features/home/home_page.dart';
import '../features/library/library_page.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/player/player_page.dart';
import '../features/playlist/playlist_page.dart';
import '../features/settings/settings_page.dart';
import 'shell.dart';

/// Every path in the app.
abstract final class Routes {
  static const home = '/home';
  static const library = '/library';
  static const settings = '/settings';
  static const welcome = '/welcome';
  static const player = '/player';
  static String playlist(int id) => '/playlist/$id';
}

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// The app's routes; [onboarded] picks the first screen.
GoRouter buildRouter({required bool onboarded}) => GoRouter(
  navigatorKey: _rootKey,
  initialLocation: onboarded ? Routes.home : Routes.welcome,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.home,
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: HomePage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.library,
              pageBuilder: (context, state) => NoTransitionPage(
                child: LibraryPage(
                  offline: state.uri.queryParameters['view'] == 'offline',
                ),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.settings,
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: SettingsPage()),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      parentNavigatorKey: _rootKey,
      path: '/playlist/:id',
      pageBuilder: (context, state) => CupertinoPage<void>(
        key: state.pageKey,
        child: PlaylistPage(id: int.parse(state.pathParameters['id']!)),
      ),
    ),
    GoRoute(
      parentNavigatorKey: _rootKey,
      path: Routes.player,
      pageBuilder: (context, state) => fadePage(state, const PlayerPage()),
    ),
    GoRoute(
      parentNavigatorKey: _rootKey,
      path: Routes.welcome,
      pageBuilder: (context, state) => fadePage(state, const OnboardingPage()),
    ),
  ],
);

/// Full-screen pages fade in; nothing slides or bounces.
Page<void> fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: VMotion.standard,
    reverseTransitionDuration: VMotion.standard,
    transitionsBuilder: (context, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: VMotion.curve),
      child: child,
    ),
  );
}

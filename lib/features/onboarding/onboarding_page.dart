import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_ink.dart';
import '../../data/providers.dart';
import '../library/import_sheet.dart';

/// First launch: what Idris is, and the first playlist link.
class OnboardingPage extends ConsumerWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pad = MediaQuery.paddingOf(context);
    return CupertinoPageScaffold(
      backgroundColor: VInk.surfaceOf(context),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, pad.top + 72, 20, pad.bottom + 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ID\nRIS', style: VText.doto(62, weight: 900, height: 0.9)),
            const SizedBox(height: 18),
            Text(
              'Your mantras and calm music, from your own YouTube playlists '
              '— nothing else. Cached as you listen, so they play without '
              'buffering, and offline.',
              style: VText.inter(15, weight: 300, height: 1.45),
            ),
            const SizedBox(height: 48),
            Text('YOUTUBE PLAYLIST LINK', style: VText.eyebrow),
            const SizedBox(height: 12),
            ImportForm(
              onImported: (id) {
                // This page leaves the stack with go(), so push through the
                // router, not this page's context.
                final router = GoRouter.of(context);
                router.go(Routes.home);
                unawaited(router.push(Routes.playlist(id)));
              },
            ),
            const SizedBox(height: 18),
            Center(
              child: VLink(
                'Skip for now',
                onTap: () async {
                  await ref.read(libraryProvider).setPref('onboarded', 'true');
                  if (context.mounted) context.go(Routes.home);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idris/features/settings/update.dart';
import 'package:idris/platform/updater.dart';

/// An updater held at one state, for drawing the card and sheet.
class _Held extends Updater {
  _Held(this.held);
  final UpdateState held;
  final calls = <String>[];

  @override
  UpdateState build() => held;

  @override
  Future<void> download() async => calls.add('download');

  @override
  Future<void> install() async => calls.add('install');

  @override
  Future<void> allowInstalls() async => calls.add('allow');
}

const _release = UpdateRelease(
  version: '1.1.0',
  notes: ['Idris updates itself', 'Smoother tabs'],
  url: 'u',
  sha256: 's',
  size: 44 * 1024 * 1024,
  versionCode: 2002,
);

/// The update card and its sheet, in every state.
void main() {
  final states = <String, (UpdateState, String)>{
    'available': (const UpdateAvailable(_release), 'Update · 44 MB'),
    'downloading': (
      const UpdateDownloading(_release, 11 * 1024 * 1024),
      '11 MB of 44 MB',
    ),
    'ready': (const UpdateReady(_release, '/x.apk'), 'Install'),
    'needs permission': (
      const UpdateNeedsPermission(_release, '/x.apk'),
      'Allow',
    ),
    'installing': (
      const UpdateInstalling(_release, '/x.apk', confirming: true),
      'Confirm on the screen Android shows',
    ),
    'failed': (
      const UpdateFailed(
        'The download was damaged. Try again.',
        release: _release,
      ),
      'Try again',
    ),
    'signed differently': (
      const UpdateFailed('Reinstall once', release: _release, reinstall: true),
      'Open GitHub',
    ),
  };

  for (final MapEntry(:key, value: (held, button)) in states.entries) {
    testWidgets(key, (t) async {
      t.view.physicalSize = const Size(1170, 2532);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final updater = _Held(held);
      await t.pumpWidget(
        ProviderScope(
          overrides: [updaterProvider.overrideWith(() => updater)],
          child: const CupertinoApp(
            home: CupertinoPageScaffold(
              child: SafeArea(child: UpdateCard(closable: true)),
            ),
          ),
        ),
      );
      expect(find.text('Idris 1.1.0 is out'), findsOneWidget);
      await t.tap(find.text('Idris 1.1.0 is out'));
      // Let the sheet finish sliding up (a spinner may keep turning).
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Idris 1.1.0'), findsOneWidget);
      expect(find.text('Smoother tabs'), findsOneWidget);
      expect(find.textContaining(button), findsWidgets);
      if (held is UpdateAvailable) {
        await t.tap(find.text('Update · 44 MB'));
        expect(updater.calls, ['download']);
      }
      if (held is UpdateReady) {
        await t.tap(find.text('Install'));
        expect(updater.calls, ['install']);
      }
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 1));
    });
  }

  testWidgets('a closed card stays hidden for that version', (t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          updaterProvider.overrideWith(
            () => _Held(const UpdateAvailable(_release)),
          ),
          dismissedUpdateProvider.overrideWith(_Dismissed.new),
        ],
        child: const CupertinoApp(
          home: CupertinoPageScaffold(
            child: SafeArea(child: UpdateCard(closable: true)),
          ),
        ),
      ),
    );
    expect(find.text('Idris 1.1.0 is out'), findsNothing);
  });
}

class _Dismissed extends DismissedUpdate {
  @override
  String? build() => '1.1.0';
}

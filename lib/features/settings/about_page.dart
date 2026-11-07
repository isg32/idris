import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/v_text.dart';
import '../../core/widgets/v_list.dart';
import '../../core/widgets/v_page.dart';
import '../../platform/crash_log.dart';

/// The version shown in About (keep in step with pubspec.yaml).
const String kAppVersion = '1.0.0';

/// Settings → Idris: the app's mark, what it is, the licences and who made
/// it (as Veronica's About).
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const _licences = [
    ('Doto', 'OFL'),
    ('Inter', 'OFL'),
    ('NewPipe Extractor', 'GPL-3.0'),
    ('youtube_explode_dart', 'BSD-3'),
    ('OkHttp', 'Apache 2.0'),
    ('just_audio', 'MIT'),
    ('audio_service', 'MIT'),
    ('drift', 'MIT'),
    ('nothing_glyph_interface', 'MIT'),
  ];

  @override
  Widget build(BuildContext context) {
    return VDetailPage(
      backLabel: 'Settings',
      title: 'About',
      children: [
        const _AppMark(),
        VListSection(
          header: const VEyebrow('Licences'),
          children: [
            for (final (name, licence) in _licences)
              VListRow(title: name, value: licence),
          ],
        ),
        VListSection(
          header: const VEyebrow('Developer'),
          children: [
            VListRow(
              leading: ClipOval(
                child: Image.asset(
                  'assets/images/developer.jpg',
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                ),
              ),
              title: 'Sapan Gajjar',
              subtitle: "You've probably guessed who made this app",
              chevron: false,
            ),
            for (final (title, handle, url) in const [
              ('GitHub', 'isg32', 'https://github.com/isg32'),
              (
                'LinkedIn',
                'sapangajjar101105',
                'https://www.linkedin.com/in/sapangajjar101105/',
              ),
            ])
              VListRow(
                title: title,
                value: handle,
                onTap: () => launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                ),
              ),
          ],
        ),
        VListSection(
          header: const VEyebrow('Help'),
          children: [
            VListRow(
              title: 'See a test crash report',
              subtitle: 'What Idris shows if something goes wrong',
              onTap: CrashLog.instance.test,
            ),
          ],
        ),
        const VFootnote(
          'Audio from your own YouTube playlists — nothing else. '
          'Nothing is collected or sent anywhere but YouTube.',
        ),
      ],
    );
  }
}

/// The app's icon, big, with the name in Doto, the version and a line.
class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Image.asset(
            'assets/icon/icon-base.png',
            width: 150,
            height: 150,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 18),
          Text('Idris', style: VText.doto(40, height: 1)),
          const SizedBox(height: 8),
          Text('Version $kAppVersion', style: VText.inter(13, weight: 300)),
          const SizedBox(height: 4),
          Text(
            'Your mantras and calm music, cached as you listen.',
            textAlign: TextAlign.center,
            style: VText.secondary,
          ),
        ],
      ),
    );
  }
}

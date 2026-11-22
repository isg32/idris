import 'package:flutter/widgets.dart';

/// Which of Idris's three layouts fits the window, by its size (so a
/// phone, a tablet, the Linux app and a resized window each get theirs):
///
/// - [mobile]: the phone layout, a tab bar and a mini player.
/// - [tablet]: a rail of section icons, the now-playing bar along the
///   bottom, and pages that use the width.
/// - [desktop]: the sidebar with the playlists, and pages in columns.
///
/// A phone on its side is wide but short: it stays [mobile], since a rail
/// and a bottom bar would leave too little height.
enum VLayout {
  mobile,
  tablet,
  desktop;

  static VLayout of(BuildContext context) =>
      forSize(MediaQuery.sizeOf(context));

  static VLayout forSize(Size s) {
    if (s.width >= 1100 && s.height >= 560) return desktop;
    if (s.width >= 640 && s.height >= 520) return tablet;
    return mobile;
  }

  /// The tablet and desktop layouts: the frame around the pages
  /// (lib/app/desktop.dart) stands in for the tab bar and mini player.
  bool get framed => this != mobile;
}

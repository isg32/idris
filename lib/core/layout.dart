import 'package:flutter/widgets.dart';

/// Which of Idris's three layouts fits the window, by its size (so a
/// phone, a tablet, the Linux app and a resized window each get theirs):
///
/// - [mobile]: the phone layout, a tab bar and a mini player.
/// - [tablet]: a rail of section icons, the now-playing bar along the
///   bottom, and pages that use the width.
/// - [desktop]: the sidebar with the playlists, and pages in columns.
///
/// A phone on its side is wide but short: it gets the [tablet] frame, as
/// the rail on the left and the bar at the bottom take far less height than
/// the floating tab bar and mini player ([sideways] tells it apart).
enum VLayout {
  mobile,
  tablet,
  desktop;

  static VLayout of(BuildContext context) =>
      forSize(MediaQuery.sizeOf(context));

  static VLayout forSize(Size s) {
    if (s.width >= 1100 && s.height >= 560) return desktop;
    if (s.width >= 640 && (s.height >= 520 || s.width > s.height)) {
      return tablet;
    }
    return mobile;
  }

  /// Wide and too short for the tablet's pages as they are (a phone on its
  /// side): the player puts its controls and lyrics side by side.
  static bool sideways(BuildContext context) {
    final s = MediaQuery.sizeOf(context);
    return s.width > s.height && s.height < 520;
  }

  /// The tablet and desktop layouts: the frame around the pages
  /// (lib/app/desktop.dart) stands in for the tab bar and mini player.
  bool get framed => this != mobile;
}

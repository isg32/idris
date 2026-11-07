import 'package:flutter/widgets.dart';

/// The only colours Idris may use (Veronica's palette).
///
/// The app is pure black and white: white on black in dark mode, black on
/// white in light mode (it follows the system; see `VPalette`). Translucency exists only for the glass
/// surfaces listed in `design/DESIGN.md`; each has its own named constant so
/// nothing else can sneak in. `test/design/no_banned_colors_test.dart` fails
/// the build if a colour is created anywhere outside this file.
abstract final class VColors {
  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);
  static const Color transparent = Color(0x00000000);

  /// Floating tab bar: white at 10 %.
  static const Color glassBar = Color(0x1AFFFFFF);

  /// Glass card over a full-screen prompt: white at 8 %.
  static const Color glassCard = Color(0x14FFFFFF);

  /// Bottom sheet: black at 55 %.
  static const Color glassSheet = Color(0x8C000000);

  /// Light mode: tab bar is black at 6 %.
  static const Color glassBarLight = Color(0x0F000000);

  /// Light mode: glass card is black at 5 %.
  static const Color glassCardLight = Color(0x0D000000);

  /// Light mode: bottom sheet is white at 60 %.
  static const Color glassSheetLight = Color(0x99FFFFFF);

  /// Veil over the blurred artwork behind the player (Settings → Artwork,
  /// experimental): black at 40 %, so white ink stays readable on any
  /// thumbnail. The artwork itself is the one place colour comes in.
  static const Color artScrim = Color(0x66000000);

  /// Light mode: white at 55 %.
  static const Color artScrimLight = Color(0x8CFFFFFF);

  /// Opacity of a disabled primary action.
  static const double disabledOpacity = 0.35;

  /// The colour that sits on top of [color] (black on white, white on black).
  static Color onColor(Color color) => color == white ? black : white;
}

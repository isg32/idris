import 'package:flutter/widgets.dart';

import 'v_colors.dart';

/// Black and white, resolved for the system brightness.
///
/// Dark mode is white ink on black paper; light mode swaps them. There is no
/// in-app toggle: Idris follows the system setting.
class VPalette {
  const VPalette._(this.brightness);

  static const VPalette dark = VPalette._(Brightness.dark);
  static const VPalette light = VPalette._(Brightness.light);

  factory VPalette.of(BuildContext context) =>
      MediaQuery.platformBrightnessOf(context) == Brightness.light
      ? light
      : dark;

  final Brightness brightness;

  bool get isDark => brightness == Brightness.dark;

  /// Text, lines and icons.
  Color get ink => isDark ? VColors.white : VColors.black;

  /// The page background.
  Color get paper => isDark ? VColors.black : VColors.white;

  Color get glassBar => isDark ? VColors.glassBar : VColors.glassBarLight;
  Color get glassCard => isDark ? VColors.glassCard : VColors.glassCardLight;
  Color get artScrim => isDark ? VColors.artScrim : VColors.artScrimLight;
  Color get glassSheet => isDark ? VColors.glassSheet : VColors.glassSheetLight;
}

import 'dart:io';

import 'package:flutter/foundation.dart';

/// On a desktop (Linux), Idris lays itself out for a window: a sidebar and
/// a now-playing bar around the pages (lib/app/desktop.dart) instead of the
/// phone's tab bar and mini player. Decided by the platform, not the
/// window's width, so a phone on its side stays a phone.
final bool desktopLayout = !kIsWeb && Platform.isLinux;

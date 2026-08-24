import 'package:flutter/foundation.dart';

/// One design, two sets of chrome. Layout, color, type, and components
/// are identical on both platforms; the chrome layer swaps the app-bar
/// alignment and back affordance, overflow glyph, menus, alerts, sheet
/// handles, and button radius.
enum GolemChrome {
  cupertino,
  android;

  /// Resolved from the target platform so `debugDefaultTargetPlatformOverride`
  /// drives tests and goldens. macOS (and desktop dev hosts) read as
  /// cupertino.
  static GolemChrome get current => switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.fuchsia => GolemChrome.android,
    _ => GolemChrome.cupertino,
  };

  /// Platform accessibility minimum for every interactive target. Visuals may
  /// remain smaller inside this hit box.
  double get minimumTapTarget => switch (this) {
    GolemChrome.cupertino => 44,
    GolemChrome.android => 48,
  };
}

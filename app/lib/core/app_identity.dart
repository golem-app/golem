import 'package:flutter/services.dart' show appFlavor;

/// The three shipped flavor identities.
///
/// `appFlavor` is a compile-time constant injected by `--flavor` (or by the
/// pubspec `default-flavor`, which host-side `flutter test` runs inherit).
/// It is null in flavorless Xcode builds (`xcodebuild -scheme Runner`), which
/// resolve to [qa] — the same identity their bundle ids and artwork carry, so
/// no build path can mint a fourth app.
enum AppIdentity {
  production('Golem', 'app.golem'),
  qa('Golem QA', 'app.golem.qa'),
  dev('Golem Dev', 'app.golem.dev');

  const AppIdentity(this.displayName, this.applicationId);

  /// The launcher/display name for this flavor.
  final String displayName;

  /// The Android application ID / iOS bundle identifier for this flavor.
  final String applicationId;

  /// Whether this identity may expose internal tools and diagnostic seams.
  ///
  /// This is deliberately flavor policy, not build-mode policy: qa release
  /// builds retain their evidence surfaces, while production stays clean in
  /// debug as well as release.
  bool get internalToolsEnabled => switch (this) {
    qa || dev => true,
    production => false,
  };

  /// The bundled app-icon tile for in-app surfaces (the drawer header).
  String get iconAsset => 'assets/images/golem_app_icon_$name.png';

  /// The identity of the running build.
  static AppIdentity get current => forFlavor(appFlavor);

  /// Maps a flavor name to its identity; null and unrecognized flavors
  /// resolve to [qa], whose all-fakes wiring is the safe fallback for a
  /// build that never said what it was.
  static AppIdentity forFlavor(String? flavor) => switch (flavor) {
    'production' => production,
    'qa' => qa,
    'dev' => dev,
    _ => qa,
  };
}

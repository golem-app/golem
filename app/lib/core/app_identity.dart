import 'package:flutter/services.dart' show appFlavor;

/// The three shipped flavor identities plus the flavorless legacy one.
///
/// `appFlavor` is a compile-time constant injected by `--flavor` (or by the
/// pubspec `default-flavor`, which host-side `flutter test` runs inherit).
/// It is null in flavorless Xcode builds (`xcodebuild -scheme Runner`),
/// which keep the legacy `app.golem.flutter` identity.
enum AppIdentity {
  production('Golem', 'app.golem'),
  qa('Golem QA', 'app.golem.qa'),
  dev('Golem Dev', 'app.golem.dev'),
  flutter('Golem Flutter', 'app.golem.flutter');

  const AppIdentity(this.displayName, this.applicationId);

  /// The launcher/display name for this flavor.
  final String displayName;

  /// The Android application ID / iOS bundle identifier for this flavor.
  final String applicationId;

  /// Whether this identity may expose internal tools and diagnostic seams.
  ///
  /// This is deliberately flavor policy, not build-mode policy: qa release
  /// builds retain their evidence surfaces, while production and the legacy
  /// flavorless identity stay clean in debug as well as release.
  bool get internalToolsEnabled => switch (this) {
    qa || dev => true,
    production || flutter => false,
  };

  /// The bundled app-icon tile for in-app surfaces (the drawer header).
  /// The flavorless legacy identity shows the production artwork, matching
  /// the flavorless macOS catalog written by tool/prepare_launcher.dart.
  String get iconAsset => switch (this) {
    flutter => 'assets/images/golem_app_icon_${production.name}.png',
    _ => 'assets/images/golem_app_icon_$name.png',
  };

  /// The identity of the running build.
  static AppIdentity get current => forFlavor(appFlavor);

  /// Maps a flavor name to its identity; null and unrecognized flavors
  /// resolve to the flavorless legacy [flutter] identity.
  static AppIdentity forFlavor(String? flavor) => switch (flavor) {
    'production' => production,
    'qa' => qa,
    'dev' => dev,
    _ => flutter,
  };
}

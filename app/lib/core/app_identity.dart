import 'package:flutter/services.dart' show appFlavor;

/// The three shipped app identities, keyed by build flavor.
///
/// `appFlavor` is a compile-time constant injected by `--flavor` (or by the
/// pubspec `default-flavor`, which host-side `flutter test` runs inherit).
/// It is null in flavorless Xcode builds, which resolve to the production
/// identity.
enum AppIdentity {
  production('Golem', 'app.golem'),
  qa('Golem QA', 'app.golem.qa'),
  dev('Golem Dev', 'app.golem.dev');

  const AppIdentity(this.displayName, this.applicationId);

  /// The launcher/display name for this flavor.
  final String displayName;

  /// The Android application ID / iOS bundle identifier for this flavor.
  final String applicationId;

  /// The identity of the running build.
  static AppIdentity get current => forFlavor(appFlavor);

  /// Maps a flavor name to its identity; unknown and null flavors resolve to
  /// [production].
  static AppIdentity forFlavor(String? flavor) => switch (flavor) {
    'qa' => qa,
    'dev' => dev,
    _ => production,
  };
}

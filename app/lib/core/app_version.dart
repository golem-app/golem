/// The user-facing app version shown in Settings ▸ About.
///
/// Kept as a hand-owned constant instead of a platform-channel lookup
/// (package_info) so the value is available synchronously and in tests; a
/// guard test compares it against `pubspec.yaml`'s version so the two can
/// never drift.
const appVersion = '1.0.0';

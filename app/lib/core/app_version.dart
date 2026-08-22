/// The user-facing app version shown in Settings ▸ About.
///
/// Kept as a hand-owned constant instead of a platform-channel lookup
/// (package_info) so the value is available synchronously and in tests; a
/// guard test compares it against `pubspec.yaml`'s version so the two can
/// never drift.
const appVersion = '1.0.0';

/// The commit a device build was made from, stamped by
/// `tool/device_install.sh` (`GOLEM_BUILD_STAMP`); empty for any other
/// build. A trailing `+` marks an uncommitted working tree.
const buildStamp = String.fromEnvironment('GOLEM_BUILD_STAMP');

/// What Settings ▸ About prints: the version, and the commit when a device
/// build carries one — so a tester can tell which build is in hand.
String aboutVersionLabel({
  String version = appVersion,
  String stamp = buildStamp,
}) => stamp.isEmpty ? version : '$version · $stamp';

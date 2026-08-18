import 'dart:io';

/// `Platform.resolvedExecutable` under `flutter test` is `flutter_tester`,
/// buried in the SDK's artifact cache, so the Dart binary is found by walking
/// up to whichever ancestor holds one.
///
/// Shared by the suites that run a repo-root tool rather than restating its
/// rules, so the local gate and CI cannot disagree about what the tool checks.
String dartExecutable() {
  for (
    var dir = File(Platform.resolvedExecutable).parent;
    dir.path != dir.parent.path;
    dir = dir.parent
  ) {
    final dart = File('${dir.path}/bin/cache/dart-sdk/bin/dart');
    if (dart.existsSync()) return dart.path;
  }
  throw StateError('No Dart SDK above ${Platform.resolvedExecutable}');
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Runs `tool/check_toolchain.dart` rather than restating its rules, so the
/// local gate and CI cannot disagree about whether the pin is held. The tool
/// owns every assertion; this exists because `flutter test` is the gate that
/// actually gets run while CI is disabled.
void main() {
  test('the toolchain pin is held', () {
    final dart = _dartExecutable();
    final result = Process.runSync(dart, [
      'run',
      'tool/check_toolchain.dart',
    ], workingDirectory: '..');
    expect(
      result.exitCode,
      0,
      reason:
          'tool/check_toolchain.dart failed:\n${result.stderr}${result.stdout}',
    );
  });
}

/// `Platform.resolvedExecutable` under `flutter test` is `flutter_tester`,
/// buried in the SDK's artifact cache, so the Dart binary is found by walking
/// up to whichever ancestor holds one.
String _dartExecutable() {
  for (
    var dir = File(Platform.resolvedExecutable).parent;
    dir.path != dir.parent.path;
    dir = dir.parent
  ) {
    final dart = File('${dir.path}/bin/cache/dart-sdk/bin/dart');
    if (dart.existsSync()) return dart.path;
  }
  fail('No Dart SDK above ${Platform.resolvedExecutable}');
}

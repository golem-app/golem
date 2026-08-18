import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/dart_executable.dart';

/// Runs `tool/check_toolchain.dart` rather than restating its rules, so the
/// local gate and CI cannot disagree about whether the pin is held. The tool
/// owns every assertion; this exists because `flutter test` is the gate that
/// actually gets run while CI is disabled.
void main() {
  test('the toolchain pin is held', () {
    final result = Process.runSync(dartExecutable(), [
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

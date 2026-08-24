import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/dart_executable.dart';

/// Runs `tool/check_feature_imports.dart` rather than restating the direction,
/// so the local gate and CI cannot disagree about which feature may import
/// which. The tool owns every assertion, and the direction it encodes is
/// decided in `docs/decisions/0015-feature-layering.md`; this exists because
/// `flutter test` is the gate that actually gets run while CI is disabled.
void main() {
  test('feature imports run downward through the recorded direction', () {
    final result = Process.runSync(dartExecutable(), [
      'run',
      'tool/check_feature_imports.dart',
    ], workingDirectory: '..');
    expect(
      result.exitCode,
      0,
      reason:
          'tool/check_feature_imports.dart failed:\n'
          '${result.stderr}${result.stdout}',
    );
  });
}

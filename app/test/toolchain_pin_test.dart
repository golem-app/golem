import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `.fvmrc` is the only place the SDK version is written. fvm reads it
/// locally and `subosito/flutter-action` reads it in CI; these assertions
/// stop a second literal from reappearing and drifting (#128).
///
/// The companion `tool/check_toolchain.dart` additionally compares the pin
/// against the SDK actually running, which only means something outside the
/// test process.
void main() {
  final pin = _pin();

  test('.fvmrc names a version', () {
    expect(pin, isNotEmpty);
  });

  test('the pubspec floor is the pinned version', () {
    final match = RegExp(
      r"""^\s+flutter:\s*['"]?>=([\d.]+)""",
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(match?.group(1), pin);
  });

  test('CI reads the pin instead of naming a version', () {
    final source = File('../.github/workflows/ci.yml').readAsStringSync();
    expect(
      RegExp(r'^\s*flutter-version:', multiLine: true).hasMatch(source),
      isFalse,
      reason: 'ci.yml must use flutter-version-file: .fvmrc',
    );
    expect(
      RegExp(
        r'^\s*flutter-version-file:\s*\.fvmrc\s*$',
        multiLine: true,
      ).allMatches(source).length,
      RegExp('subosito/flutter-action').allMatches(source).length,
      reason: 'every job that sets up Flutter must read .fvmrc',
    );
  });

  test('the SDK checkout fvm materialises is not committed', () {
    final ignored = File('../.gitignore').readAsStringSync();
    expect(ignored, contains('.fvm/'));
  });
}

String _pin() {
  final decoded =
      jsonDecode(File('../.fvmrc').readAsStringSync()) as Map<String, dynamic>;
  return decoded['flutter'] as String;
}

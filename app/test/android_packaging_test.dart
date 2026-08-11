import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Android build settings Play compliance rests on, asserted as text
/// because no CI job builds an Android artifact and every one of them is
/// otherwise invisible until an upload is rejected.
///
/// Each is an inherited default made explicit. The uncompressed, page-aligned
/// packaging and the symbolication uploads come free from AGP 9; `targetSdk`
/// comes from the Flutter SDK; the ABI set is chosen by Flutter's Gradle plugin
/// unless told otherwise. Every one would change silently under a toolchain
/// bump.
///
/// The release-time guard that reads the artifact rather than the build files
/// is `tool/check_android_packaging.dart`.
void main() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();

  /// Matches a setting only as live code. `contains` alone would pass on a
  /// commented-out line, which is exactly how one of these disappears.
  Matcher declares(String statement) =>
      matches(RegExp('^\\s*${RegExp.escape(statement)}', multiLine: true));

  test('the NDK is pinned to the Inferno manifest revision', () {
    // The app may not import package:inferno (tool/check_inferno_imports.dart),
    // so the manifest is read as text — the constant itself is the source of
    // truth, never a literal copied into this file.
    final manifest = File(
      '../packages/inferno/lib/src/model_manifest.dart',
    ).readAsStringSync();
    final pinned = RegExp(
      r"androidNdkVersion\s*=\s*'([^']+)'",
    ).firstMatch(manifest)?.group(1);
    expect(pinned, isNotNull, reason: 'androidNdkVersion left the manifest');
    expect(gradle, declares('ndkVersion = "$pinned"'));
  });

  test('native libraries stay uncompressed and page-aligned', () {
    expect(gradle, declares('useLegacyPackaging = false'));
  });

  test('Android builds carry arm64-v8a alone', () {
    // The clear is half the override: Flutter's plugin fills this set with the
    // three ABIs it supports before the block runs, and only defaultConfig is
    // preserved (AGP merges flavor sets by union, so no flavor can narrow).
    expect(gradle, declares('abiFilters.clear()'));
    expect(gradle, declares('abiFilters.add("arm64-v8a")'));
  });

  test('the release artifact keeps what Play symbolicates crashes with', () {
    expect(gradle, declares('isMinifyEnabled = true'));
    expect(gradle, declares('debugSymbolLevel = "SYMBOL_TABLE"'));
  });

  test('the build refuses a target API below the Play floor', () {
    expect(gradle, declares('require(flutter.targetSdkVersion >= 36)'));
  });
}

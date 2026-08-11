import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Android build settings Play compliance rests on, asserted as text
/// because no CI job builds an Android artifact and every one of them is
/// otherwise invisible until an upload is rejected.
///
/// Each is an inherited default made explicit. `useLegacyPackaging` and the
/// uncompressed, page-aligned packaging behind it come free from AGP 9;
/// `targetSdk` comes from the Flutter SDK; the ABI set is chosen by Flutter's
/// Gradle plugin unless told otherwise. Every one of them would change
/// silently under a toolchain bump.
///
/// The release-time guard that reads the artifact rather than the build files
/// is `tool/check_android_packaging.dart`.
void main() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final properties = File('android/gradle.properties').readAsStringSync();

  test('the NDK is pinned to the Inferno manifest revision', () {
    // The app may not import package:inferno (tool/check_inferno_imports.dart),
    // so the literal is repeated here; androidNdkVersion in
    // packages/inferno/lib/src/model_manifest.dart is the source of truth and
    // pin_consistency_test.dart holds the hook to it.
    expect(gradle, contains('ndkVersion = "29.0.14206865"'));
  });

  test('native libraries stay uncompressed and page-aligned', () {
    expect(gradle, contains('useLegacyPackaging = false'));
  });

  test('the store artifact carries arm64-v8a alone', () {
    expect(gradle, contains('abiFilters += "arm64-v8a"'));
    // Without this the Flutter Gradle plugin clears abiFilters and restores
    // all three ABIs it supports, silently undoing the line above.
    expect(properties, contains('disable-abi-filtering=true'));
  });

  test('the build refuses a target API below the Play floor', () {
    expect(gradle, contains('require(flutter.targetSdkVersion >= 36)'));
  });
}

import 'dart:io';

import 'package:test/test.dart';

/// A delete-guard, not a drift test.
///
/// Google Play requires every 64-bit native library to support 16 KB memory
/// pages. `libinferno.so` satisfies that because the CMake target passes the
/// alignment explicitly — and only because of that: NDK r28 and later happen
/// to link 16 KB-aligned by default, but the build hook compiles with whatever
/// NDK the machine exposes, and r27 without these options emits 4 KB segments
/// Play rejects (measured, docs/decisions/0010-android-native-packaging.md).
///
/// Nothing else in the tree would notice the options being dropped: no CI job
/// builds an Android artifact, and the release check that reads the built
/// bundle runs at release time. So this test is the fast guard, and
/// `tool/check_android_packaging.dart` is the real one.
void main() {
  test('the Android link line keeps the 16 KB page-size options', () {
    final cmake = File('native/llama/CMakeLists.txt').readAsStringSync();
    expect(cmake, contains('-Wl,-z,max-page-size=16384'));
    expect(cmake, contains('-Wl,-z,common-page-size=16384'));
  });
}

import 'dart:io';

import 'package:inferno/inferno.dart';
// Not exported: the ABI number is a contract between this package and the
// two native halves, not something a consumer configures.
import 'package:inferno/src/native_backend.dart' show infernoAbiVersion;
import 'package:test/test.dart';

/// The native pins exist in more than one place by necessity (Dart manifest,
/// build hook, C++/Swift probe strings, SwiftPM lockfile). These tests make
/// the manifest the single source of truth by failing on any drift.
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('the build hook downloads the manifest llama.cpp revision', () {
    expect(read('hook/build.dart'), contains(llamaCppRevision));
  });

  test('the build hook requires the manifest Android NDK revision', () {
    expect(read('hook/build.dart'), contains(androidNdkVersion));
  });

  test('the llama shim probe reports the manifest release', () {
    expect(
      read('native/src/llama_shim.cpp'),
      contains('llama.cpp $llamaCppRelease'),
    );
  });

  test('the MLX shim probe reports the manifest versions', () {
    final shim = read(
      'native/apple/Sources/InfernoMLXCarrier/InfernoMLXShim.swift',
    );
    expect(shim, contains(mlxSwiftLmVersion));
    expect(shim, contains(mlxSwiftVersion));
  });

  test('the SwiftPM lockfile pins the manifest MLX revisions', () {
    final resolved = read('native/apple/Package.resolved');
    expect(resolved, contains(mlxSwiftLmRevision));
    expect(resolved, contains(mlxSwiftRevision));
  });

  // The ABI number exists three times by necessity: Dart checks it, the C
  // header defines it, and the Swift carrier answers it over a separate
  // entry point. A shim that reports a number it does not implement fails at
  // load with a version mismatch instead of at the feature that is missing —
  // the presence penalty ABI 4 added is silently dropped rather than refused
  // (#130).
  test('the C header defines the ABI this package speaks', () {
    expect(
      read('native/include/inferno.h'),
      contains('#define INFERNO_ABI_VERSION $infernoAbiVersion'),
    );
  });

  test('the MLX carrier reports the ABI this package speaks', () {
    expect(
      read('native/apple/Sources/InfernoMLXCarrier/InfernoMLXShim.swift'),
      contains('let infernoMlxABI: UInt32 = $infernoAbiVersion'),
    );
  });

  test('the SwiftPM manifest requests the manifest MLX revisions', () {
    // Package.swift drives resolution; the lockfile only records it. Both
    // must carry the pin or a bump to one silently drifts the other.
    final manifest = read('native/apple/Package.swift');
    expect(manifest, contains(mlxSwiftLmRevision));
    expect(manifest, contains(mlxSwiftRevision));
  });
}
